#!/usr/bin/env bash
# shellcheck disable=SC1090

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Usage: "pihole -g"
# Compiles a list of ad-serving domains by downloading them from multiple sources
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

export LC_ALL=C

coltable="/opt/pihole/COL_TABLE"
source "${coltable}"
regexconverter="/opt/pihole/wildcard_regex_converter.sh"
source "${regexconverter}"

basename="pihole"
PIHOLE_COMMAND="/usr/local/bin/${basename}"

piholeDir="/etc/${basename}"

adListFile="${piholeDir}/adlists.list"
adListDefault="${piholeDir}/adlists.default"

whitelistFile="${piholeDir}/whitelist.txt"
blacklistFile="${piholeDir}/blacklist.txt"
regexFile="${piholeDir}/regex.list"

adList="${piholeDir}/gravity.list"
blackList="${piholeDir}/black.list"
localList="${piholeDir}/local.list"
VPNList="/etc/openvpn/ipp.txt"

domainsExtension="domains"
matterAndLight="${basename}.0.matterandlight.txt"
parsedMatter="${basename}.1.parsedmatter.txt"
whitelistMatter="${basename}.2.whitelistmatter.txt"
accretionDisc="${basename}.3.accretionDisc.txt"
preEventHorizon="list.preEventHorizon"

skipDownload="false"

resolver="pihole-FTL"

haveSourceUrls=true

# Source setupVars from install script
setupVars="${piholeDir}/setupVars.conf"
if [[ -f "${setupVars}" ]];then
  source "${setupVars}"

  # Remove CIDR mask from IPv4/6 addresses
  IPV4_ADDRESS="${IPV4_ADDRESS%/*}"
  IPV6_ADDRESS="${IPV6_ADDRESS%/*}"

  # Determine if IPv4/6 addresses exist
  if [[ -z "${IPV4_ADDRESS}" ]] && [[ -z "${IPV6_ADDRESS}" ]]; then
    echo -e "  ${COL_LIGHT_RED}No IP addresses found! Please run 'pihole -r' to reconfigure${COL_NC}"
    exit 1
  fi
else
  echo -e "  ${COL_LIGHT_RED}Installation Failure: ${setupVars} does not exist! ${COL_NC}
  Please run 'pihole -r', and choose the 'reconfigure' option to fix."
  exit 1
fi

# Source pihole-FTL from install script
pihole_FTL="${piholeDir}/pihole-FTL.conf"
if [[ -f "${pihole_FTL}" ]]; then
  source "${pihole_FTL}"
fi

if [[ -z "${BLOCKINGMODE}" ]] ; then
  BLOCKINGMODE="NULL"
fi

# Determine if superseded pihole.conf exists
if [[ -r "${piholeDir}/pihole.conf" ]]; then
  echo -e "  ${COL_LIGHT_RED}Ignoring overrides specified within pihole.conf! ${COL_NC}"
fi

# Determine if Pi-hole blocking is disabled
# If this is the case, we want to update
#  gravity.list.bck and black.list.bck instead of
#  gravity.list and black.list
detect_pihole_blocking_status() {
  if [[ "${BLOCKING_ENABLED}" == false ]]; then
    echo -e "  ${INFO} Pi-hole blocking is disabled"
    adList="${adList}.bck"
    blackList="${blackList}.bck"
  else
    echo -e "  ${INFO} Pi-hole blocking is enabled"
  fi
}

# Determine if DNS resolution is available before proceeding
gravity_CheckDNSResolutionAvailable() {
  local lookupDomain="pi.hole"

  # Determine if $localList does not exist
  if [[ ! -e "${localList}" ]]; then
    lookupDomain="raw.githubusercontent.com"
  fi

  # Determine if $lookupDomain is resolvable
  if timeout 1 getent hosts "${lookupDomain}" &> /dev/null; then
    # Print confirmation of resolvability if it had previously failed
    if [[ -n "${secs:-}" ]]; then
      echo -e "${OVER}  ${TICK} DNS resolution is now available\\n"
    fi
    return 0
  elif [[ -n "${secs:-}" ]]; then
    echo -e "${OVER}  ${CROSS} DNS resolution is not available"
    exit 1
  fi

  # If the /etc/resolv.conf contains resolvers other than 127.0.0.1 then the local dnsmasq will not be queried and pi.hole is NXDOMAIN.
  # This means that even though name resolution is working, the getent hosts check fails and the holddown timer keeps ticking and eventualy fails
  # So we check the output of the last command and if it failed, attempt to use dig +short as a fallback
  if timeout 1 dig +short "${lookupDomain}" &> /dev/null; then
    if [[ -n "${secs:-}" ]]; then
      echo -e "${OVER}  ${TICK} DNS resolution is now available\\n"
    fi
    return 0
  elif [[ -n "${secs:-}" ]]; then
    echo -e "${OVER}  ${CROSS} DNS resolution is not available"
    exit 1
  fi

  # Determine error output message
  if pidof ${resolver} &> /dev/null; then
    echo -e "  ${CROSS} DNS resolution is currently unavailable"
  else
    echo -e "  ${CROSS} DNS service is not running"
    "${PIHOLE_COMMAND}" restartdns
  fi

  # Ensure DNS server is given time to be resolvable
  secs="120"
  echo -ne "  ${INFO} Time until retry: ${secs}"
  until timeout 1 getent hosts "${lookupDomain}" &> /dev/null; do
    [[ "${secs:-}" -eq 0 ]] && break
    echo -ne "${OVER}  ${INFO} Time until retry: ${secs}"
    : $((secs--))
    sleep 1
  done

  # Try again
  gravity_CheckDNSResolutionAvailable
}

# Retrieve blocklist URLs and parse domains from adlists.list
gravity_GetBlocklistUrls() {
  echo -e "  ${INFO} ${COL_BOLD}Neutrino emissions detected${COL_NC}..."

  if [[ -f "${adListDefault}" ]] && [[ -f "${adListFile}" ]]; then
    # Remove superceded $adListDefault file
    rm "${adListDefault}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to remove ${adListDefault}"
  fi

  # Retrieve source URLs from $adListFile
  # Logic: Remove comments and empty lines
  mapfile -t sources <<< "$(grep -v -E "^(#|$)" "${adListFile}" 2> /dev/null)"

  # Parse source domains from $sources
  mapfile -t sourceDomains <<< "$(
    # Logic: Split by folder/port
    awk -F '[/:]' '{
      # Remove URL protocol & optional username:password@
      gsub(/(.*:\/\/|.*:.*@)/, "", $0)
      if(length($1)>0){print $1}
      else {print "local"}
    }' <<< "$(printf '%s\n' "${sources[@]}")" 2> /dev/null
  )"

  local str="Pulling blocklist source list into range"

  if [[ -n "${sources[*]}" ]] && [[ -n "${sourceDomains[*]}" ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${INFO} No source list found, or it is empty"
    echo ""
    haveSourceUrls=false
  fi
}

# Define options for when retrieving blocklists
gravity_SetDownloadOptions() {
  local url domain agent cmd_ext str

  echo ""

  # Loop through $sources and download each one
  for ((i = 0; i < "${#sources[@]}"; i++)); do
    url="${sources[$i]}"
    domain="${sourceDomains[$i]}"

    # Save the file as list.#.domain
    saveLocation="${piholeDir}/list.${i}.${domain}.${domainsExtension}"
    activeDomains[$i]="${saveLocation}"

    # Default user-agent (for Cloudflare's Browser Integrity Check: https://support.cloudflare.com/hc/en-us/articles/200170086-What-does-the-Browser-Integrity-Check-do-)
    agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"

    # Provide special commands for blocklists which may need them
    case "${domain}" in
      "pgl.yoyo.org") cmd_ext="-d mimetype=plaintext -d hostformat=hosts";;
      *) cmd_ext="";;
    esac

    if [[ "${skipDownload}" == false ]]; then
      echo -e "  ${INFO} Target: ${domain} (${url##*/})"
      gravity_DownloadBlocklistFromUrl "${url}" "${cmd_ext}" "${agent}"
      echo ""
    fi
  done
  gravity_Blackbody=true
}

# Download specified URL and perform checks on HTTP status and file content
gravity_DownloadBlocklistFromUrl() {
  local url="${1}" cmd_ext="${2}" agent="${3}" heisenbergCompensator="" patternBuffer str httpCode success=""

  # Create temp file to store content on disk instead of RAM
  patternBuffer=$(mktemp -p "/tmp" --suffix=".phgpb")

  # Determine if $saveLocation has read permission
  if [[ -r "${saveLocation}" && $url != "file"* ]]; then
    # Have curl determine if a remote file has been modified since last retrieval
    # Uses "Last-Modified" header, which certain web servers do not provide (e.g: raw github urls)
    # Note: Don't do this for local files, always download them
    heisenbergCompensator="-z ${saveLocation}"
  fi

  str="Status:"
  echo -ne "  ${INFO} ${str} Pending..."
  blocked=false
  case $BLOCKINGMODE in
    "IP-NODATA-AAAA"|"IP")
        if [[ $(dig "${domain}" +short | grep "${IPV4_ADDRESS}" -c) -ge 1 ]]; then
          blocked=true
        fi;;
    "NXDOMAIN")
        if [[ $(dig "${domain}" | grep "NXDOMAIN" -c) -ge 1 ]]; then
          blocked=true
        fi;;
    "NULL"|*)
        if [[ $(dig "${domain}" +short | grep "0.0.0.0" -c) -ge 1 ]]; then
          blocked=true
        fi;;
   esac

  if [[ "${blocked}" == true ]]; then
    ip=$(dig "@${PIHOLE_DNS_1}" +short "${domain}")
    if [[ $(echo "${url}" | awk -F '://' '{print $1}') = "https" ]]; then
      port=443;
    else port=80
    fi
    bad_list=$(pihole -q -adlist hosts-file.net | head -n1 | awk -F 'Match found in ' '{print $2}')
    echo -e "${OVER}  ${CROSS} ${str} ${domain} is blocked by ${bad_list%:}. Using DNS on ${PIHOLE_DNS_1} to download ${url}";
    echo -ne "  ${INFO} ${str} Pending..."
    cmd_ext="--resolve $domain:$port:$ip $cmd_ext"
  fi
  # shellcheck disable=SC2086
  httpCode=$(curl -s -L ${cmd_ext} ${heisenbergCompensator} -w "%{http_code}" -A "${agent}" "${url}" -o "${patternBuffer}" 2> /dev/null)

  case $url in
    # Did we "download" a local file?
    "file"*)
        if [[ -s "${patternBuffer}" ]]; then
          echo -e "${OVER}  ${TICK} ${str} Retrieval successful"; success=true
        else
          echo -e "${OVER}  ${CROSS} ${str} Not found / empty list"
        fi;;
    # Did we "download" a remote file?
    *)
      # Determine "Status:" output based on HTTP response
      case "${httpCode}" in
        "200") echo -e "${OVER}  ${TICK} ${str} Retrieval successful"; success=true;;
        "304") echo -e "${OVER}  ${TICK} ${str} No changes detected"; success=true;;
        "000") echo -e "${OVER}  ${CROSS} ${str} Connection Refused";;
        "403") echo -e "${OVER}  ${CROSS} ${str} Forbidden";;
        "404") echo -e "${OVER}  ${CROSS} ${str} Not found";;
        "408") echo -e "${OVER}  ${CROSS} ${str} Time-out";;
        "451") echo -e "${OVER}  ${CROSS} ${str} Unavailable For Legal Reasons";;
        "500") echo -e "${OVER}  ${CROSS} ${str} Internal Server Error";;
        "504") echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Gateway)";;
        "521") echo -e "${OVER}  ${CROSS} ${str} Web Server Is Down (Cloudflare)";;
        "522") echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Cloudflare)";;
        *    ) echo -e "${OVER}  ${CROSS} ${str} ${url} (${httpCode})";;
      esac;;
  esac

  # Determine if the blocklist was downloaded and saved correctly
  if [[ "${success}" == true ]]; then
    if [[ "${httpCode}" == "304" ]]; then
      : # Do not attempt to re-parse file
    # Check if $patternbuffer is a non-zero length file
    elif [[ -s "${patternBuffer}" ]]; then
      # Determine if blocklist is non-standard and parse as appropriate
      gravity_ParseFileIntoDomains "${patternBuffer}" "${saveLocation}"
    else
      # Fall back to previously cached list if $patternBuffer is empty
      echo -e "  ${INFO} Received empty file: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
    fi
  else
    # Determine if cached list has read permission
    if [[ -r "${saveLocation}" ]]; then
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
    else
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_RED}no cached list available${COL_NC}"
    fi
  fi
}

# Parse source files into domains format
gravity_ParseFileIntoDomains() {
  local source="${1}" destination="${2}" firstLine abpFilter

  # Determine if we are parsing a consolidated list
  if [[ "${source}" == "${piholeDir}/${matterAndLight}" ]]; then
    # Remove comments and print only the domain name
    # Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
    # This helps with that and makes it easier to read
    # It also helps with debugging so each stage of the script can be researched more in depth
    # Awk -F splits on given IFS, we grab the right hand side (chops trailing #coments and /'s to grab the domain only.
    # Last awk command takes non-commented lines and if they have 2 fields, take the right field (the domain) and leave
    # the left (IP address), otherwise grab the single field.

    < ${source} awk -F '#' '{print $1}' | \
    awk -F '/' '{print $1}' | \
    awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' | \
    sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${destination}
    return 0
  fi

  # Individual file parsing: Keep comments, while parsing domains from each line
  # We keep comments to respect the list maintainer's licensing
  read -r firstLine < "${source}"

  # Determine how to parse individual source file formats
  if [[ "${firstLine,,}" =~ (adblock|ublock|^!) ]]; then
    # Compare $firstLine against lower case words found in Adblock lists
    echo -ne "  ${INFO} Format: Adblock"

    # Define symbols used as comments: [!
    # "||.*^" includes the "Example 2" domains we can extract
    # https://adblockplus.org/filter-cheatsheet
    abpFilter="/^(\\[|!)|^(\\|\\|.*\\^)/"

    # Parse Adblock lists by extracting "Example 2" domains
    # Logic: Ignore lines which do not include comments or domain name anchor
    awk ''"${abpFilter}"' {
      # Remove valid adblock type options
      gsub(/\$?~?(important|third-party|popup|subdocument|websocket),?/, "", $0)
      # Remove starting domain name anchor "||" and ending seperator "^"
      gsub(/^(\|\|)|(\^)/, "", $0)
      # Remove invalid characters (*/,=$)
      if($0 ~ /[*\/,=\$]/) { $0="" }
      # Remove lines which are only IPv4 addresses
      if($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { $0="" }
      if($0) { print $0 }
    }' "${source}" > "${destination}"

    # Determine if there are Adblock exception rules
    # https://adblockplus.org/filters
    if grep -q "^@@||" "${source}" &> /dev/null; then
      # Parse Adblock lists by extracting exception rules
      # Logic: Ignore lines which do not include exception format "@@||example.com^"
      awk -F "[|^]" '/^@@\|\|.*\^/ {
        # Remove valid adblock type options
        gsub(/\$?~?(third-party)/, "", $0)
        # Remove invalid characters (*/,=$)
        if($0 ~ /[*\/,=\$]/) { $0="" }
        if($3) { print $3 }
      }' "${source}" > "${destination}.exceptionsFile.tmp"

      # Remove exceptions
      comm -23 "${destination}" <(sort "${destination}.exceptionsFile.tmp") > "${source}"
      mv "${source}" "${destination}"
    fi

    echo -e "${OVER}  ${TICK} Format: Adblock"
  elif grep -q "^address=/" "${source}" &> /dev/null; then
    # Parse Dnsmasq format lists
    echo -e "  ${CROSS} Format: Dnsmasq (list type not supported)"
  elif grep -q -E "^https?://" "${source}" &> /dev/null; then
    # Parse URL list if source file contains "http://" or "https://"
    # Scanning for "^IPv4$" is too slow with large (1M) lists on low-end hardware
    echo -ne "  ${INFO} Format: URL"

    awk '
      # Remove URL scheme, optional "username:password@", and ":?/;"
      # The scheme must be matched carefully to avoid blocking the wrong URL
      # in cases like:
      #   http://www.evil.com?http://www.good.com
      # See RFC 3986 section 3.1 for details.
      /[:?\/;]/ { gsub(/(^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/(.*:.*@)?|[:?\/;].*)/, "", $0) }
      # Skip lines which are only IPv4 addresses
      /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { next }
      # Print if nonempty
      length { print }
    ' "${source}" 2> /dev/null > "${destination}"

    echo -e "${OVER}  ${TICK} Format: URL"
  else
    # Default: Keep hosts/domains file in same format as it was downloaded
    output=$( { mv "${source}" "${destination}"; } 2>&1 )

    if [[ ! -e "${destination}" ]]; then
      echo -e "\\n  ${CROSS} Unable to move tmp file to ${piholeDir}
    ${output}"
      gravity_Cleanup "error"
    fi
  fi
}

# Create (unfiltered) "Matter and Light" consolidated list
gravity_ConsolidateDownloadedBlocklists() {
  local str lastLine

  str="Consolidating blocklists"
  if [[ "${haveSourceUrls}" == true ]]; then
    echo -ne "  ${INFO} ${str}..."
  fi

  # Empty $matterAndLight if it already exists, otherwise, create it
  : > "${piholeDir}/${matterAndLight}"

  # Loop through each *.domains file
  for i in "${activeDomains[@]}"; do
    # Determine if file has read permissions, as download might have failed
    if [[ -r "${i}" ]]; then
      # Remove windows CRs from file, convert list to lower case, and append into $matterAndLight
      tr -d '\r' < "${i}" | tr '[:upper:]' '[:lower:]' >> "${piholeDir}/${matterAndLight}"

      # Ensure that the first line of a new list is on a new line
      lastLine=$(tail -1 "${piholeDir}/${matterAndLight}")
      if [[ "${#lastLine}" -gt 0 ]]; then
        echo "" >> "${piholeDir}/${matterAndLight}"
      fi
    fi
  done
  if [[ "${haveSourceUrls}" == true ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
  fi
}

# Parse consolidated list into (filtered, unique) domains-only format
gravity_SortAndFilterConsolidatedList() {
  local str num

  str="Extracting domains from blocklists"
  if [[ "${haveSourceUrls}" == true ]]; then
    echo -ne "  ${INFO} ${str}..."
  fi

  # Parse into hosts file
  gravity_ParseFileIntoDomains "${piholeDir}/${matterAndLight}" "${piholeDir}/${parsedMatter}"

  # Format $parsedMatter line total as currency
  num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${parsedMatter}")")
  if [[ "${haveSourceUrls}" == true ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
  fi
  echo -e "  ${INFO} Number of domains being pulled in by gravity: ${COL_BLUE}${num}${COL_NC}"

  str="Removing duplicate domains"
  if [[ "${haveSourceUrls}" == true ]]; then
    echo -ne "  ${INFO} ${str}..."
  fi

  sort -u "${piholeDir}/${parsedMatter}" > "${piholeDir}/${preEventHorizon}"

  if [[ "${haveSourceUrls}" == true ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
    # Format $preEventHorizon line total as currency
    num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
    echo -e "  ${INFO} Number of unique domains trapped in the Event Horizon: ${COL_BLUE}${num}${COL_NC}"
  fi
}

# Whitelist user-defined domains
gravity_Whitelist() {
  local num str

  if [[ ! -f "${whitelistFile}" ]]; then
    echo -e "  ${INFO} Nothing to whitelist!"
    return 0
  fi

  num=$(wc -l < "${whitelistFile}")
  str="Number of whitelisted domains: ${num}"
  echo -ne "  ${INFO} ${str}..."

  # Print everything from preEventHorizon into whitelistMatter EXCEPT domains in $whitelistFile
  comm -23 "${piholeDir}/${preEventHorizon}" <(sort "${whitelistFile}") > "${piholeDir}/${whitelistMatter}"

  echo -e "${OVER}  ${INFO} ${str}"
}

# Output count of blacklisted domains and regex filters
gravity_ShowBlockCount() {
  local num

  if [[ -f "${blacklistFile}" ]]; then
    num=$(printf "%'.0f" "$(wc -l < "${blacklistFile}")")
    echo -e "  ${INFO} Number of blacklisted domains: ${num}"
  fi

  if [[ -f "${regexFile}" ]]; then
    num=$(grep -cv "^#" "${regexFile}")
    echo -e "  ${INFO} Number of regex filters: ${num}"
  fi
}

# Parse list of domains into hosts format
gravity_ParseDomainsIntoHosts() {
  awk -v ipv4="$IPV4_ADDRESS" -v ipv6="$IPV6_ADDRESS" '{
    # Remove windows CR line endings
    sub(/\r$/, "")
    # Parse each line as "ipaddr domain"
    if(ipv6 && ipv4) {
      print ipv4" "$0"\n"ipv6" "$0
    } else if(!ipv6) {
      print ipv4" "$0
    } else {
      print ipv6" "$0
    }
  }' >> "${2}" < "${1}"
}

# Create "localhost" entries into hosts format
gravity_ParseLocalDomains() {
  local hostname

  if [[ -s "/etc/hostname" ]]; then
    hostname=$(< "/etc/hostname")
  elif command -v hostname &> /dev/null; then
    hostname=$(hostname -f)
  else
    echo -e "  ${CROSS} Unable to determine fully qualified domain name of host"
    return 0
  fi

  echo -e "${hostname}\\npi.hole" > "${localList}.tmp"

  # Empty $localList if it already exists, otherwise, create it
  : > "${localList}"

  gravity_ParseDomainsIntoHosts "${localList}.tmp" "${localList}"

  # Add additional LAN hosts provided by OpenVPN (if available)
  if [[ -f "${VPNList}" ]]; then
    awk -F, '{printf $2"\t"$1".vpn\n"}' "${VPNList}" >> "${localList}"
  fi
}

# Create primary blacklist entries
gravity_ParseBlacklistDomains() {
  local output status

  # Empty $accretionDisc if it already exists, otherwise, create it
  : > "${piholeDir}/${accretionDisc}"

  if [[ -f "${piholeDir}/${whitelistMatter}" ]]; then
    mv "${piholeDir}/${whitelistMatter}" "${piholeDir}/${accretionDisc}"
  else
    # There was no whitelist file, so use preEventHorizon instead of whitelistMatter.
    mv "${piholeDir}/${preEventHorizon}" "${piholeDir}/${accretionDisc}"
  fi

  # Move the file over as /etc/pihole/gravity.list so dnsmasq can use it
  output=$( { mv "${piholeDir}/${accretionDisc}" "${adList}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to move ${accretionDisc} from ${piholeDir}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

# Create user-added blacklist entries
gravity_ParseUserDomains() {
  if [[ ! -f "${blacklistFile}" ]]; then
    return 0
  fi
  # Copy the file over as /etc/pihole/black.list so dnsmasq can use it
  cp "${blacklistFile}" "${blackList}" 2> /dev/null || \
    echo -e "\\n  ${CROSS} Unable to move ${blacklistFile##*/} to ${piholeDir}"
}

# Trap Ctrl-C
gravity_Trap() {
  trap '{ echo -e "\\n\\n  ${INFO} ${COL_LIGHT_RED}User-abort detected${COL_NC}"; gravity_Cleanup "error"; }' INT
}

# Clean up after Gravity upon exit or cancellation
gravity_Cleanup() {
  local error="${1:-}"

  str="Cleaning up stray matter"
  echo -ne "  ${INFO} ${str}..."

  # Delete tmp content generated by Gravity
  rm ${piholeDir}/pihole.*.txt 2> /dev/null
  rm ${piholeDir}/*.tmp 2> /dev/null
  rm /tmp/*.phgpb 2> /dev/null

  # Ensure this function only runs when gravity_SetDownloadOptions() has completed
  if [[ "${gravity_Blackbody:-}" == true ]]; then
    # Remove any unused .domains files
    for file in ${piholeDir}/*.${domainsExtension}; do
      # If list is not in active array, then remove it
      if [[ ! "${activeDomains[*]}" == *"${file}"* ]]; then
        rm -f "${file}" 2> /dev/null || \
          echo -e "  ${CROSS} Failed to remove ${file##*/}"
      fi
    done
  fi

  echo -e "${OVER}  ${TICK} ${str}"

  # Only restart DNS service if offline
  if ! pidof ${resolver} &> /dev/null; then
    "${PIHOLE_COMMAND}" restartdns
    dnsWasOffline=true
  fi

  # Print Pi-hole status if an error occured
  if [[ -n "${error}" ]]; then
    "${PIHOLE_COMMAND}" status
    exit 1
  fi
}

helpFunc() {
  echo "Usage: pihole -g
Update domains from blocklists specified in adlists.list

Options:
  -f, --force          Force the download of all specified blocklists
  -h, --help           Show this help dialog"
  exit 0
}

for var in "$@"; do
  case "${var}" in
    "-f" | "--force" ) forceDelete=true;;
    "-h" | "--help" ) helpFunc;;
    "-sd" | "--skip-download" ) skipDownload=true;;
    "-b" | "--blacklist-only" ) listType="blacklist";;
    "-w" | "--whitelist-only" ) listType="whitelist";;
    "-wild" | "--wildcard-only" ) listType="wildcard"; dnsRestartType="restart";;
  esac
done

# Trap Ctrl-C
gravity_Trap

if [[ "${forceDelete:-}" == true ]]; then
  str="Deleting existing list cache"
  echo -ne "${INFO} ${str}..."

  rm /etc/pihole/list.* 2> /dev/null || true
  echo -e "${OVER}  ${TICK} ${str}"
fi

detect_pihole_blocking_status

# Determine which functions to run
if [[ "${skipDownload}" == false ]]; then
  # Gravity needs to download blocklists
  gravity_CheckDNSResolutionAvailable
  gravity_GetBlocklistUrls
  if [[ "${haveSourceUrls}" == true ]]; then
    gravity_SetDownloadOptions
  fi
  gravity_ConsolidateDownloadedBlocklists
  gravity_SortAndFilterConsolidatedList
else
  # Gravity needs to modify Blacklist/Whitelist/Wildcards
  echo -e "  ${INFO} Using cached Event Horizon list..."
  numberOf=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
  echo -e "  ${INFO} ${COL_BLUE}${numberOf}${COL_NC} unique domains trapped in the Event Horizon"
fi

# Perform when downloading blocklists, or modifying the whitelist
if [[ "${skipDownload}" == false ]] || [[ "${listType}" == "whitelist" ]]; then
  gravity_Whitelist
fi

convert_wildcard_to_regex
gravity_ShowBlockCount

# Perform when downloading blocklists, or modifying the white/blacklist (not wildcards)
if [[ "${skipDownload}" == false ]] || [[ "${listType}" == *"list" ]]; then
  str="Parsing domains into hosts format"
  echo -ne "  ${INFO} ${str}..."

  gravity_ParseUserDomains

  # Perform when downloading blocklists
  if [[ ! "${listType:-}" == "blacklist" ]]; then
    gravity_ParseLocalDomains
    gravity_ParseBlacklistDomains
  fi

  echo -e "${OVER}  ${TICK} ${str}"

  gravity_Cleanup
fi

echo ""

# Determine if DNS has been restarted by this instance of gravity
if [[ -z "${dnsWasOffline:-}" ]]; then
  # Use "force-reload" when restarting dnsmasq for everything but Wildcards
  "${PIHOLE_COMMAND}" restartdns "${dnsRestartType:-force-reload}"
fi
"${PIHOLE_COMMAND}" status
