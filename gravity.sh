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

coltable="/opt/pihole/COL_TABLE"
source "${coltable}"

basename="pihole"
PIHOLE_COMMAND="/usr/local/bin/${basename}"
WHITELIST_COMMAND="${PIHOLE_COMMAND} -w"

piholeDir="/etc/${basename}"
piholeRepo="/etc/.${basename}"

adListFile="${piholeDir}/adlists.list"
adListDefault="${piholeDir}/adlists.default"
adListRepoDefault="${piholeRepo}/adlists.default"

whitelistFile="${piholeDir}/whitelist.txt"
blacklistFile="${piholeDir}/blacklist.txt"
wildcardFile="/etc/dnsmasq.d/03-pihole-wildcard.conf"

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

# Use "force-reload" when restarting dnsmasq for everything but Wildcards
dnsRestart="force-reload"

# Source setupVars from install script
setupVars="${piholeDir}/setupVars.conf"
if [[ -f "${setupVars}" ]];then
  source "${setupVars}"

  # Remove CIDR mask from IPv4/6 addresses
  IPV4_ADDRESS="${IPV4_ADDRESS%/*}"
  IPV6_ADDRESS="${IPV6_ADDRESS%/*}"
else
  echo -e "  ${COL_LIGHT_RED}Installation Failure: ${setupVars} does not exist! ${COL_NC}
  Please run 'pihole -r', and choose the 'reconfigure' option to fix."
  exit 1
fi

# Warn users still using pihole.conf that it no longer has any effect
if [[ -r "${piholeDir}/pihole.conf" ]]; then
  echo -e "  ${COL_LIGHT_RED}Ignoring overrides specified within pihole.conf! ${COL_NC}"
fi

# Determine if DNS resolution is available before proceeding with retrieving blocklists
gravity_DNSLookup() {
  local lookupDomain plu

  # Determine which domain to resolve depending on existence of $localList
  if [[ -e "${localList}" ]]; then
    lookupDomain="pi.hole"
  else
    lookupDomain="raw.githubusercontent.com"
  fi

  # Determine if domain can be resolved
  if ! timeout 10 nslookup "${lookupDomain}" > /dev/null; then
    if [[ -n "${secs}" ]]; then
      echo -e "${OVER}  ${CROSS} DNS resolution is still unavailable, cancelling"
      exit 1
    fi

    # Determine error output message
    if pidof dnsmasq > /dev/null; then
      echo -e "  ${CROSS} DNS resolution is temporarily unavailable"
    else
      echo -e "  ${CROSS} DNS service is not running"
      "${PIHOLE_COMMAND}" restartdns
    fi

    # Give time for dnsmasq to be resolvable
    secs="30"
    while [[ "${secs}" -ne 0 ]]; do
      [[ "${secs}" -ne 1 ]] && plu="s" || plu=""
      echo -ne "${OVER}  ${INFO} Waiting $secs second${plu} before continuing..."
      sleep 1
      : $((secs--))
    done

    # Try again
    gravity_DNSLookup
  elif [[ -n "${secs}" ]]; then
    # Print confirmation of resolvability if it had previously failed
    echo -e "${OVER}  ${TICK} DNS resolution is now available\\n"
  fi
}

# Retrieve blocklist URLs and parse domains from adlists.list
gravity_Collapse() {
  echo -e "  ${INFO} Neutrino emissions detected..."

  # Handle "adlists.list" and "adlists.default" files
  if [[ -f "${adListDefault}" ]] && [[ -f "${adListFile}" ]]; then
    # Remove superceded $adListDefault file
    rm "${adListDefault}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to remove ${adListDefault}"
  elif [[ ! -f "${adListFile}" ]]; then
    # Create "adlists.list" by copying "adlists.default" from internal Pi-hole repo
    cp "${adListRepoDefault}" "${adListFile}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to copy ${adListFile##*/} from ${piholeRepo}"
  fi

  local str="Pulling blocklist source list into range"
  echo -ne "  ${INFO} ${str}..."

  # Retrieve source URLs from $adListFile
  # Awk Logic: Remove comments, CR line endings and empty lines
  mapfile -t sources < <(awk '!/^[#@;!\[]/ {gsub(/\r$/, "", $0); if ($1) { print $1 } }' "${adListFile}" 2> /dev/null)

  # Parse source domains from $sources
  # Awk Logic: Split by folder/port, remove URL protocol & optional username:password@
  mapfile -t sourceDomains < <(
    awk -F '[/:]' '{
      gsub(/(.*:\/\/|.*:.*@)/, "", $0)
      print $1
    }' <<< "$(printf '%s\n' "${sources[@]}")" 2> /dev/null
  )

  if [[ -n "${sources[*]}" ]] && [[ -n "${sourceDomains[*]}" ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    gravity_Cleanup "error"
  fi
}

# Define options for when retrieving blocklists
gravity_Supernova() {
  local url domain agent cmd_ext str

  echo ""

  # Loop through $sources to download each one
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
      str="Target: ${domain} (${url##*/})"
      echo -e "  ${INFO} ${str}"

      gravity_Pull "${url}" "${cmd_ext}" "${agent}" "${str}"

      echo ""
    fi
  done
}

# Download specified URL and perform QA
gravity_Pull() {
  local url cmd_ext agent heisenbergCompensator patternBuffer str httpCode success

  url="${1}"
  cmd_ext="${2}"
  agent="${3}"

  # Store downloaded content to temp file instead of RAM
  patternBuffer=$(mktemp)

  heisenbergCompensator=""
  if [[ -r "${saveLocation}" ]]; then
    # Allow curl to determine if a remote file has been modified since last retrieval
    heisenbergCompensator="-z ${saveLocation}"
  fi

  str="Status:"
  echo -ne "  ${INFO} ${str} Pending..."
  # shellcheck disable=SC2086
  httpCode=$(curl -s -L ${cmd_ext} ${heisenbergCompensator} -w "%{http_code}" -A "${agent}" "${url}" -o "${patternBuffer}" 2> /dev/null)

  # Determine "Status:" output based on HTTP response
  case "${httpCode}" in
    "200" ) echo -e "${OVER}  ${TICK} ${str} Retrieval successful"; success="true";;
    "304" ) echo -e "${OVER}  ${TICK} ${str} No changes detected"; success="true";;
    "403" ) echo -e "${OVER}  ${CROSS} ${str} Forbidden"; success="false";;
    "404" ) echo -e "${OVER}  ${CROSS} ${str} Not found"; success="false";;
    "408" ) echo -e "${OVER}  ${CROSS} ${str} Time-out"; success="false";;
    "451" ) echo -e "${OVER}  ${CROSS} ${str} Unavailable For Legal Reasons"; success="false";;
    "521" ) echo -e "${OVER}  ${CROSS} ${str} Web Server Is Down (Cloudflare)"; success="false";;
    "522" ) echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Cloudflare)"; success="false";;
    "500" ) echo -e "${OVER}  ${CROSS} ${str} Internal Server Error"; success="false";;
    *     ) echo -e "${OVER}  ${CROSS} ${str} Status ${httpCode}"; success="false";;
  esac

  # Determine if the blocklist was downloaded and saved correctly
  if [[ "${success}" == "true" ]]; then
    if [[ "${httpCode}" == "304" ]]; then
      : # Do nothing
    # Check if patternbuffer is a non-zero length file
    elif [[ -s "${patternBuffer}" ]]; then
      # Determine if blocklist is non-standard and parse as appropriate
      gravity_ParseFileIntoDomains "${patternBuffer}" "${saveLocation}"
    else
      # Fall back to previously cached list if patternBuffer is empty
      echo -e "  ${INFO} Received empty file: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
    fi
  else
    # Determine if cached list exists
    if [[ -r "${saveLocation}" ]]; then
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
    else
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_RED}no cached list available${COL_NC}"
    fi
  fi

  # Delete temp file if it has not been moved
  if [[ -f "${patternBuffer}" ]]; then
    rm "${patternBuffer}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to remove ${patternBuffer}"
  fi
}

# Parse non-standard source files into domains-only format
gravity_ParseFileIntoDomains() {
  local source destination commentPattern firstLine abpFilter
  source="${1}"
  destination="${2}"

  # Determine how to parse source file
  if [[ "${source}" == "${piholeDir}/${matterAndLight}" ]]; then
    # Consolidated list parsing: Remove comments and hosts IP's

    # Define symbols used as comments: #;@![/
    commentPattern="[#;@![\\/]"

    # Awk Logic: Process lines which do not begin with comments
    awk '!/^'"${commentPattern}"'/ {
      # If there are multiple words seperated by space
      if (NF>1) {
        # Remove comments (including prefixed spaces/tabs)
        if ($0 ~ /'"${commentPattern}"'/) { gsub("( |\t)'"${commentPattern}"'.*", "", $0) }
        # Print consecutive domains
        if ($3) {
          $1=""
          # Remove space which is left in $0 when removing $1
          gsub("^ ", "", $0)
          print $0
        # Print single domain
        } else if ($2) {
          print $2
        }
      # If there are no words seperated by space
      } else if($1) {
        print $1
      }
    }' "${source}" 2> /dev/null > "${destination}"
  else
    # Individual file parsing: Keep comments, while parsing domains from each line
    read -r firstLine < "${source}"

    # Determine how to parse individual source file formats
    # Lists may not capitalise the first line correctly, so compare strings against lower case
    if [[ "${firstLine,,}" =~ "adblock" ]] || [[ "${firstLine,,}" =~ "ublock" ]] || [[ "${firstLine,,}" =~ "! checksum" ]]; then
      # Awk Logic: Parse Adblock domains & comments: https://adblockplus.org/filter-cheatsheet 
      abpFilter="/^(\\[|!)|^(\\|\\|.*\\^)/"
      awk ''"${abpFilter}"' {
        # Remove valid adblock type options
        gsub(/~?(important|third-party|popup|subdocument|websocket),?/, "", $0)
        # Remove starting domain name anchor "||" and ending seperator "^$" ($ optional)
        gsub(/(\|\||\^\$?$)/, "", $0)
        # Remove lines which are only IPv4 addresses or contain "^/*"
        if ($0 ~ /(^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|[\\^\/\*])/) { $0="" }
        if ($0) { print $0 }
      }' "${source}" 2> /dev/null > "${destination}"
    elif grep -q -E "^(https?://|([0-9]{1,3}\\.){3}[0-9]{1,3}$)" "${source}" &> /dev/null; then
      # Parse URLs if source file contains http:// or IPv4
      awk '{
        # Remove URL protocol, optional "username:password@", and ":?/;"
        if ($0 ~ /[:?\/;]/) { gsub(/(^.*:\/\/(.*:.*@)?|[:?\/;].*)/, "", $0) }
        # Remove lines which are only IPv4 addresses
        if ($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { $0="" }
        if ($0) { print $0 }
      }' "${source}" 2> /dev/null > "${destination}"
    else
      # Keep hosts/domains file in same format as it was downloaded
      output=$( { mv "${source}" "${destination}"; } 2>&1 )
      status="$?"

      if [[ "${status}" -ne 0 ]]; then
        echo -e "  ${CROSS} Unable to move tmp file to ${piholeDir}
      ${output}"
        gravity_Cleanup "error"
      fi
    fi
  fi
}

# Create unfiltered "Matter and Light" consolidated list
gravity_Schwarzschild() {
  local str lastLine

  str="Consolidating blocklists"
  echo -ne "  ${INFO} ${str}..."

  # Empty $matterAndLight if it already exists, otherwise, create it
  : > "${piholeDir}/${matterAndLight}"

  for i in "${activeDomains[@]}"; do
    # Only assimilate list if it is available (download might have failed permanently)
    if [[ -r "${i}" ]]; then
      # Compile all blacklisted domains into one file and remove CRs
      tr -d '\r' < "${i}" >> "${piholeDir}/${matterAndLight}"

      # Ensure each source blocklist has a final newline
      lastLine=$(tail -1 "${piholeDir}/${matterAndLight}")
      [[ "${#lastLine}" -gt 0 ]] && echo "" >> "${piholeDir}/${matterAndLight}"
    fi
  done

  echo -e "${OVER}  ${TICK} ${str}"
}

# Parse unfiltered consolidated blocklist into filtered domains-only format
gravity_Filter() {
  local str num

  str="Extracting domains from blocklists"
  echo -ne "  ${INFO} ${str}..."

  # Parse into hosts file
  gravity_ParseFileIntoDomains "${piholeDir}/${matterAndLight}" "${piholeDir}/${parsedMatter}"

  # Format file line count as currency
  num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${parsedMatter}")")
  echo -e "${OVER}  ${TICK} ${str}
  ${INFO} ${COL_LIGHT_BLUE}${num}${COL_NC} domains being pulled in by gravity"

  gravity_Unique
}

# Sort and remove duplicate blacklisted domains
gravity_Unique() {
  local str num

  str="Removing duplicate domains"
  echo -ne "  ${INFO} ${str}..."
  sort -u "${piholeDir}/${parsedMatter}" > "${piholeDir}/${preEventHorizon}"
  echo -e "${OVER}  ${TICK} ${str}"

  # Format file line count as currency
  num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
  echo -e "  ${INFO} ${COL_LIGHT_BLUE}${num}${COL_NC} unique domains trapped in the Event Horizon"
}

# Whitelist blocklist domain sources
gravity_WhitelistBLD() {
  local plural str uniqDomains

  echo ""
  plural=; [[ "${#sources[*]}" != "1" ]] && plural=s
  str="Adding blocklist source${plural} to the whitelist"
  echo -ne "  ${INFO} ${str}..."

  # Create array of unique $sourceDomains
  # Disable SC2046 as quoting will only return first domain
  # shellcheck disable=SC2046
  read -r -a uniqDomains <<< $(awk '{ if(!a[$1]++) { print $1 } }' <<< "$(printf '%s\n' "${sourceDomains[@]}")")

  ${WHITELIST_COMMAND} -nr -q "${uniqDomains[*]}" > /dev/null

  echo -e "${OVER}  ${TICK} ${str}"
}

# Whitelist user-defined domains
gravity_Whitelist() {
  local plural str num

  # Test existence of whitelist.txt
  if [[ -f "${whitelistFile}" ]]; then
    # Remove anything in whitelist.txt from the Event Horizon
    num=$(wc -l < "${whitelistFile}")
    plural=; [[ "${num}" != "1" ]] && plural=s
    str="Whitelisting ${num} domain${plural}"
    echo -ne "  ${INFO} ${str}..."

    # Print everything from preEventHorizon into whitelistMatter EXCEPT domains in whitelist.txt
    grep -F -x -v -f "${whitelistFile}" "${piholeDir}/${preEventHorizon}" > "${piholeDir}/${whitelistMatter}"

    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "  ${INFO} Nothing to whitelist!"
  fi
}

# Output count of blacklisted domains and wildcards
gravity_ShowBlockCount() {
  local num plural str

  if [[ -f "${blacklistFile}" ]]; then
    num=$(printf "%'.0f" "$(wc -l < "${blacklistFile}")")
    plural=; [[ "${num}" != "1" ]] && plural=s
    str="Exact blocked domain${plural}: ${num}"
    echo -e "  ${INFO} ${str}"
  else
    echo -e "  ${INFO} Nothing to blacklist!"
  fi

  if [[ -f "${wildcardFile}" ]]; then
    num=$(grep -c "^" "${wildcardFile}")
    # If IPv4 and IPv6 is used, divide total wildcard count by 2
    if [[ -n "${IPV4_ADDRESS}" ]] && [[ -n "${IPV6_ADDRESS}" ]];then
      num=$(( num/2 ))
    fi
    plural=; [[ "${num}" != "1" ]] && plural=s
    echo -e "  ${INFO} Wildcard blocked domain${plural}: ${num}"
  else
    echo -e "  ${INFO} No wildcards used!"
  fi
}

# Parse list of domains into hosts format
gravity_ParseDomainsIntoHosts() {
  if [[ -n "${IPV4_ADDRESS}" ]] || [[ -n "${IPV6_ADDRESS}" ]]; then
    # Awk Logic: Remove CR line endings and print IP before domain if IPv4/6 is used
    awk -v ipv4addr="$IPV4_ADDRESS" -v ipv6addr="$IPV6_ADDRESS" '{
      sub(/\r$/, "")
      if(ipv4addr) { print ipv4addr" "$0; }
      if(ipv6addr) { print ipv6addr" "$0; }
    }' >> "${2}" < "${1}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}No IP addresses found! Please run 'pihole -r' to reconfigure${COL_NC}\\n"
    gravity_Cleanup "error"
  fi
}

# Create "localhost" entries into hosts format
gravity_ParseLocalDomains() {
  local hostname

  if [[ -f "/etc/hostname" ]]; then
    hostname=$(< "/etc/hostname")
  elif command -v hostname &> /dev/null; then
    hostname=$(hostname -f)
  else
    echo -e "  ${CROSS} Unable to determine fully qualified domain name of host"
  fi

  echo -e "${hostname}\\npi.hole" > "${localList}.tmp"
  # Copy the file over as /etc/pihole/local.list so dnsmasq can use it
  rm "${localList}" 2> /dev/null || true
  gravity_ParseDomainsIntoHosts "${localList}.tmp" "${localList}"
  rm "${localList}.tmp" 2> /dev/null || true

  # Add additional local hosts provided by OpenVPN (if available)
  if [[ -f "${VPNList}" ]]; then
    awk -F, '{printf $2"\t"$1"\n"}' "${VPNList}" >> "${localList}"
  fi
}

# Create primary blacklist entries
gravity_ParseBlacklistDomains() {
  local output status

  # Empty $accretionDisc if it already exists, otherwise, create it
  : > "${piholeDir}/${accretionDisc}"

  gravity_ParseDomainsIntoHosts "${piholeDir}/${whitelistMatter}" "${piholeDir}/${accretionDisc}"

  # Move the file over as /etc/pihole/gravity.list so dnsmasq can use it
  output=$( { mv "${piholeDir}/${accretionDisc}" "${adList}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "  ${CROSS} Unable to move ${accretionDisc} from ${piholeDir}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

# Create user-added blacklist entries
gravity_ParseUserDomains() {
  if [[ -f "${blacklistFile}" ]]; then
    gravity_ParseDomainsIntoHosts "${blacklistFile}" "${blackList}.tmp"
    # Copy the file over as /etc/pihole/black.list so dnsmasq can use it
    mv "${blackList}.tmp" "${blackList}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to move ${blackList##*/}.tmp to ${piholeDir}"
  fi
}

# Trap Ctrl-C
gravity_Trap() {
  trap '{ echo -e "\\n\\n  ${INFO} ${COL_LIGHT_RED}User-abort detected${COL_NC}"; gravity_Cleanup "error"; }' INT
}

# Clean up after Gravity
gravity_Cleanup() {
  local error="${1:-}"

  str="Cleaning up stray matter"
  echo -ne "  ${INFO} ${str}..."

  rm ${piholeDir}/pihole.*.txt 2> /dev/null
  rm ${piholeDir}/*.tmp 2> /dev/null

  # Remove any unused .domains files
  for file in ${piholeDir}/*.${domainsExtension}; do
    # If list is not in active array, then remove it
    if [[ ! "${activeDomains[*]}" == *"${file}"* ]]; then
      rm -f "${file}" 2> /dev/null || \
        echo -e "  ${CROSS} Failed to remove ${file##*/}"
    fi
  done

  echo -e "${OVER}  ${TICK} ${str}"
  
  [[ -n "${error}" ]] && echo ""

  # Only restart DNS service if offline
  if ! pidof dnsmasq &> /dev/null; then
    "${PIHOLE_COMMAND}" restartdns
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
    "-wild" | "--wildcard-only" ) listType="wildcard";;
  esac
done

gravity_Trap

# Ensure dnsmasq is restarted when modifying wildcards
[[ "${listType}" == "wildcard" ]] && dnsRestart="restart"

if [[ "${forceDelete}" == true ]]; then
  str="Deleting exising list cache"
  echo -ne "${INFO} ${str}..."

  if rm /etc/pihole/list.* 2> /dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    exit 1
  fi
fi

# Determine which functions to run
if [[ "${skipDownload}" == false ]]; then
  # Gravity needs to download blocklists
  gravity_DNSLookup
  gravity_Collapse
  gravity_Supernova
  gravity_Schwarzschild
  gravity_Filter
  gravity_WhitelistBLD
else
  # Gravity needs to modify Blacklist/Whitelist/Wildcards
  echo -e "  ${INFO} Using cached Event Horizon list..."
  numberOf=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
  echo -e "  ${INFO} ${COL_LIGHT_BLUE}${numberOf}${COL_NC} unique domains trapped in the Event Horizon"
fi

# Perform when downloading blocklists, or modifying the whitelist
if [[ "${skipDownload}" == false ]] || [[ "${listType}" == "whitelist" ]]; then
  gravity_Whitelist
fi

gravity_ShowBlockCount

# Perform when downloading blocklists, or modifying the blacklist
if [[ "${skipDownload}" == false ]] || [[ "${listType}" == "blacklist" ]]; then
  str="Parsing domains into hosts format"
  echo -ne "  ${INFO} ${str}..."

  gravity_ParseUserDomains

  # Perform when downloading blocklists
  if [[ ! "${listType}" == "blacklist" ]]; then
    gravity_ParseLocalDomains
    gravity_ParseBlacklistDomains
  fi

  echo -e "${OVER}  ${TICK} ${str}"
fi

# Perform when downloading blocklists
if [[ "${skipDownload}" == false ]]; then
  gravity_Cleanup
fi

echo ""
"${PIHOLE_COMMAND}" restartdns "${dnsRestart}"
"${PIHOLE_COMMAND}" status
