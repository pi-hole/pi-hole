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

# Legacy (pre v5.0) list file locations
whitelistFile="${piholeDir}/whitelist.txt"
blacklistFile="${piholeDir}/blacklist.txt"
regexFile="${piholeDir}/regex.list"
adListFile="${piholeDir}/adlists.list"

localList="${piholeDir}/local.list"
VPNList="/etc/openvpn/ipp.txt"

piholeGitDir="/etc/.pihole"
gravityDBfile="${piholeDir}/gravity.db"
gravityDBschema="${piholeGitDir}/advanced/Templates/gravity.db.sql"
optimize_database=false

domainsExtension="domains"
matterAndLight="${basename}.0.matterandlight.txt"
parsedMatter="${basename}.1.parsedmatter.txt"
preEventHorizon="list.preEventHorizon"

resolver="pihole-FTL"

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

# Generate new sqlite3 file from schema template
generate_gravity_database() {
  sqlite3 "${gravityDBfile}" < "${gravityDBschema}"
}

# Import domains from file and store them in the specified database table
database_table_from_file() {
  # Define locals
  local table="${1}"
  local source="${2}"
  local backup_path="${piholeDir}/migration_backup"
  local backup_file="${backup_path}/$(basename "${2}")"

  # Create database file if not present
  if [ ! -e "${gravityDBfile}" ]; then
    echo -e "  ${INFO} Creating new gravity database"
    generate_gravity_database
  fi

  # Truncate table
  output=$( { sqlite3 "${gravityDBfile}" <<< "DELETE FROM ${table};"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to truncate ${table} database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi

  local tmpFile
  tmpFile="$(mktemp -p "/tmp" --suffix=".gravity")"
  local timestamp
  timestamp="$(date --utc +'%s')"
  local inputfile
  if [[ "${table}" == "gravity" ]]; then
    # No need to modify the input data for the gravity table
    inputfile="${source}"
  else
    # Apply format for white-, blacklist, regex, and adlists tables
    # Read file line by line
    grep -v '^ *#' < "${source}" | while IFS= read -r domain
    do
      # Only add non-empty lines
      if [[ ! -z "${domain}" ]]; then
        echo "\"${domain}\",1,${timestamp}" >> "${tmpFile}"
      fi
    done
    inputfile="${tmpFile}"
  fi
  # Store domains in database table specified by ${table}
  # Use printf as .mode and .import need to be on separate lines
  # see https://unix.stackexchange.com/a/445615/83260
  output=$( { printf ".mode csv\\n.import \"%s\" %s\\n" "${inputfile}" "${table}" | sqlite3 "${gravityDBfile}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to fill table ${table} in database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi

  # Delete tmpfile
  rm "${tmpFile}" > /dev/null 2>&1 || \
      echo -e "  ${CROSS} Unable to remove ${tmpFile}"

  # Move source file to backup directory, create directory if not existing
  mkdir -p "${backup_path}"
  mv "${source}" "${backup_file}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to remove ${source}"
}

# Migrate pre-v5.0 list files to database-based Pi-hole versions
migrate_to_database() {
  if [[ -e "${adListFile}" ]]; then
    # Store adlists domains in database
    echo -e "  ${INFO} Pi-hole upgrade: Moving content of ${adListFile} into database"
    database_table_from_file "adlists" "${adListFile}"
  fi
  if [[ -e "${blacklistFile}" ]]; then
    # Store blacklisted domains in database
    echo -e "  ${INFO} Pi-hole upgrade: Moving content of ${blacklistFile} into database"
    database_table_from_file "blacklist" "${blacklistFile}"
  fi
  if [[ -e "${whitelistFile}" ]]; then
    # Store whitelisted domains in database
    echo -e "  ${INFO} Pi-hole upgrade: Moving content of ${whitelistFile} into database"
    database_table_from_file "whitelist" "${whitelistFile}"
  fi
  if [[ -e "${regexFile}" ]]; then
    # Store regex domains in database
    echo -e "  ${INFO} Pi-hole upgrade: Moving content of ${regexFile} into database"
    database_table_from_file "regex" "${regexFile}"
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

  # Retrieve source URLs from gravity database
  # We source only enabled adlists, sqlite3 stores boolean values as 0 (false) or 1 (true)
  mapfile -t sources <<< "$(sqlite3 "${gravityDBfile}" "SELECT address FROM vw_adlists;" 2> /dev/null)"

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
    return 0
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${INFO} No source list found, or it is empty"
    echo ""
    return 1
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
    agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36"

    # Provide special commands for blocklists which may need them
    case "${domain}" in
      "pgl.yoyo.org") cmd_ext="-d mimetype=plaintext -d hostformat=hosts";;
      *) cmd_ext="";;
    esac

    echo -e "  ${INFO} Target: ${domain} (${url##*/})"
    gravity_DownloadBlocklistFromUrl "${url}" "${cmd_ext}" "${agent}"
    echo ""
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
    printf -v ip_addr "%s" "${PIHOLE_DNS_1%#*}"
    if [[ ${PIHOLE_DNS_1} != *"#"* ]]; then
        port=53
    else
        printf -v port "%s" "${PIHOLE_DNS_1#*#}"
    fi
    ip=$(dig "@${ip_addr}" -p "${port}" +short "${domain}")
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
    # 1) Remove carriage returns
    # 2) Convert all characters to lowercase
    # 3) Remove lines containing "#" or "/"
    # 4) Remove leading tabs, spaces, etc.
    # 5) Delete lines not matching domain names
    < "${source}" tr -d '\r' | \
    tr '[:upper:]' '[:lower:]' | \
    sed -r '/(\/|#).*$/d' | \
    sed -r 's/^.*\s+//g' | \
    sed -r '/([^\.]+\.)+[^\.]{2,}/!d' >  "${destination}"
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
  echo -ne "  ${INFO} ${str}..."

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
  echo -e "${OVER}  ${TICK} ${str}"

}

# Parse consolidated list into (filtered, unique) domains-only format
gravity_SortAndFilterConsolidatedList() {
  local str num

  str="Extracting domains from blocklists"
  echo -ne "  ${INFO} ${str}..."

  # Parse into file
  gravity_ParseFileIntoDomains "${piholeDir}/${matterAndLight}" "${piholeDir}/${parsedMatter}"

  # Format $parsedMatter line total as currency
  num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${parsedMatter}")")

  echo -e "${OVER}  ${TICK} ${str}"
  echo -e "  ${INFO} Gravity pulled in ${COL_BLUE}${num}${COL_NC} domains"

  str="Removing duplicate domains"
  echo -ne "  ${INFO} ${str}..."
  sort -u "${piholeDir}/${parsedMatter}" > "${piholeDir}/${preEventHorizon}"
  echo -e "${OVER}  ${TICK} ${str}"

  # Format $preEventHorizon line total as currency
  num=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
  str="Storing ${COL_BLUE}${num}${COL_NC} unique blocking domains in database"
  echo -ne "  ${INFO} ${str}..."
  database_table_from_file "gravity" "${piholeDir}/${preEventHorizon}"
  echo -e "${OVER}  ${TICK} ${str}"
}

# Report number of entries in a table
gravity_Table_Count() {
  local table="${1}"
  local str="${2}"
  local num
  num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM ${table} WHERE enabled = 1;")"
  echo -e "  ${INFO} Number of ${str}: ${num}"
}

# Output count of blacklisted domains and regex filters
gravity_ShowCount() {
  gravity_Table_Count "blacklist" "blacklisted domains"
  gravity_Table_Count "whitelist" "whitelisted domains"
  gravity_Table_Count "regex" "regex filters"
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
gravity_generateLocalList() {
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

  if ${optimize_database} ; then
    str="Optimizing domains database"
    echo -ne "  ${INFO} ${str}..."
    # Run VACUUM command on database to optimize it
    output=$( { sqlite3 "${gravityDBfile}" "VACUUM;"; } 2>&1 )
    status="$?"

    if [[ "${status}" -ne 0 ]]; then
      echo -e "\\n  ${CROSS} Unable to optimize gravity database ${gravityDBfile}\\n  ${output}"
      error="error"
    else
      echo -e "${OVER}  ${TICK} ${str}"
    fi
  fi

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
    "-o" | "--optimize" ) optimize_database=true;;
    "-h" | "--help" ) helpFunc;;
  esac
done

# Trap Ctrl-C
gravity_Trap

# Move possibly existing legacy files to the gravity database
migrate_to_database

if [[ "${forceDelete:-}" == true ]]; then
  str="Deleting existing list cache"
  echo -ne "${INFO} ${str}..."

  rm /etc/pihole/list.* 2> /dev/null || true
  echo -e "${OVER}  ${TICK} ${str}"
fi

# Gravity downloads blocklists next
gravity_CheckDNSResolutionAvailable
if gravity_GetBlocklistUrls; then
  gravity_SetDownloadOptions
  # Build preEventHorizon
  gravity_ConsolidateDownloadedBlocklists
  gravity_SortAndFilterConsolidatedList
fi

# Create local.list
gravity_generateLocalList
gravity_ShowCount

gravity_Cleanup
echo ""

# Determine if DNS has been restarted by this instance of gravity
if [[ -z "${dnsWasOffline:-}" ]]; then
  "${PIHOLE_COMMAND}" restartdns reload
fi
"${PIHOLE_COMMAND}" status
