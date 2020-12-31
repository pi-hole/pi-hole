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
# shellcheck disable=SC1091
source "/etc/.pihole/advanced/Scripts/database_migration/gravity-db.sh"

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
gravityTEMPfile="${piholeDir}/gravity_temp.db"
gravityDBschema="${piholeGitDir}/advanced/Templates/gravity.db.sql"
gravityDBcopy="${piholeGitDir}/advanced/Templates/gravity_copy.sql"

domainsExtension="domains"

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
  sqlite3 "${1}" < "${gravityDBschema}"
}

# Copy data from old to new database file and swap them
gravity_swap_databases() {
  local str
  str="Building tree"
  echo -ne "  ${INFO} ${str}..."

  # The index is intentionally not UNIQUE as prro quality adlists may contain domains more than once
  output=$( { sqlite3 "${gravityTEMPfile}" "CREATE INDEX idx_gravity ON gravity (domain, adlist_id);"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to build gravity tree in ${gravityTEMPfile}\\n  ${output}"
    return 1
  fi
  echo -e "${OVER}  ${TICK} ${str}"

  str="Swapping databases"
  echo -ne "  ${INFO} ${str}..."

  output=$( { sqlite3 "${gravityTEMPfile}" < "${gravityDBcopy}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to copy data from ${gravityDBfile} to ${gravityTEMPfile}\\n  ${output}"
    return 1
  fi
  echo -e "${OVER}  ${TICK} ${str}"

  # Swap databases and remove old database
  rm "${gravityDBfile}"
  mv "${gravityTEMPfile}" "${gravityDBfile}"
}

# Update timestamp when the gravity table was last updated successfully
update_gravity_timestamp() {
  output=$( { printf ".timeout 30000\\nINSERT OR REPLACE INTO info (property,value) values ('updated',cast(strftime('%%s', 'now') as int));" | sqlite3 "${gravityDBfile}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update gravity timestamp in database ${gravityDBfile}\\n  ${output}"
    return 1
  fi
  return 0
}

# Import domains from file and store them in the specified database table
database_table_from_file() {
  # Define locals
  local table source backup_path backup_file tmpFile type
  table="${1}"
  source="${2}"
  backup_path="${piholeDir}/migration_backup"
  backup_file="${backup_path}/$(basename "${2}")"
  tmpFile="$(mktemp -p "/tmp" --suffix=".gravity")"

  local timestamp
  timestamp="$(date --utc +'%s')"

  local rowid
  declare -i rowid
  rowid=1

  # Special handling for domains to be imported into the common domainlist table
  if [[ "${table}" == "whitelist" ]]; then
    type="0"
    table="domainlist"
  elif [[ "${table}" == "blacklist" ]]; then
    type="1"
    table="domainlist"
  elif [[ "${table}" == "regex" ]]; then
    type="3"
    table="domainlist"
  fi

  # Get MAX(id) from domainlist when INSERTing into this table
  if [[ "${table}" == "domainlist" ]]; then
    rowid="$(sqlite3 "${gravityDBfile}" "SELECT MAX(id) FROM domainlist;")"
    if [[ -z "$rowid" ]]; then
      rowid=0
    fi
    rowid+=1
  fi

  # Loop over all domains in ${source} file
  # Read file line by line
  grep -v '^ *#' < "${source}" | while IFS= read -r domain
  do
    # Only add non-empty lines
    if [[ -n "${domain}" ]]; then
      if [[ "${table}" == "domain_audit" ]]; then
        # domain_audit table format (no enable or modified fields)
        echo "${rowid},\"${domain}\",${timestamp}" >> "${tmpFile}"
      elif [[ "${table}" == "adlist" ]]; then
        # Adlist table format
        echo "${rowid},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${source}\"," >> "${tmpFile}"
      else
        # White-, black-, and regexlist table format
        echo "${rowid},${type},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${source}\"" >> "${tmpFile}"
      fi
      rowid+=1
    fi
  done

  # Store domains in database table specified by ${table}
  # Use printf as .mode and .import need to be on separate lines
  # see https://unix.stackexchange.com/a/445615/83260
  output=$( { printf ".timeout 30000\\n.mode csv\\n.import \"%s\" %s\\n" "${tmpFile}" "${table}" | sqlite3 "${gravityDBfile}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to fill table ${table}${type} in database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi

  # Move source file to backup directory, create directory if not existing
  mkdir -p "${backup_path}"
  mv "${source}" "${backup_file}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to backup ${source} to ${backup_path}"

  # Delete tmpFile
  rm "${tmpFile}" > /dev/null 2>&1 || \
    echo -e "  ${CROSS} Unable to remove ${tmpFile}"
}

# Update timestamp of last update of this list. We store this in the "old" database as all values in the new database will later be overwritten
database_adlist_updated() {
  output=$( { printf ".timeout 30000\\nUPDATE adlist SET date_updated = (cast(strftime('%%s', 'now') as int)) WHERE id = %i;\\n" "${1}" | sqlite3 "${gravityDBfile}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update timestamp of adlist with ID ${1} in database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

# Migrate pre-v5.0 list files to database-based Pi-hole versions
migrate_to_database() {
  # Create database file only if not present
  if [ ! -e "${gravityDBfile}" ]; then
    # Create new database file - note that this will be created in version 1
    echo -e "  ${INFO} Creating new gravity database"
    generate_gravity_database "${gravityDBfile}"

    # Check if gravity database needs to be updated
    upgrade_gravityDB "${gravityDBfile}" "${piholeDir}"

    # Migrate list files to new database
    if [ -e "${adListFile}" ]; then
      # Store adlist domains in database
      echo -e "  ${INFO} Migrating content of ${adListFile} into new database"
      database_table_from_file "adlist" "${adListFile}"
    fi
    if [ -e "${blacklistFile}" ]; then
      # Store blacklisted domains in database
      echo -e "  ${INFO} Migrating content of ${blacklistFile} into new database"
      database_table_from_file "blacklist" "${blacklistFile}"
    fi
    if [ -e "${whitelistFile}" ]; then
      # Store whitelisted domains in database
      echo -e "  ${INFO} Migrating content of ${whitelistFile} into new database"
      database_table_from_file "whitelist" "${whitelistFile}"
    fi
    if [ -e "${regexFile}" ]; then
      # Store regex domains in database
      # Important note: We need to add the domains to the "regex" table
      # as it will only later be renamed to "regex_blacklist"!
      echo -e "  ${INFO} Migrating content of ${regexFile} into new database"
      database_table_from_file "regex" "${regexFile}"
    fi
  fi

  # Check if gravity database needs to be updated
  upgrade_gravityDB "${gravityDBfile}" "${piholeDir}"
}

# Determine if DNS resolution is available before proceeding
gravity_CheckDNSResolutionAvailable() {
  local lookupDomain="pi.hole"

  # Determine if $localList does not exist, and ensure it is not empty
  if [[ ! -e "${localList}" ]] || [[ -s "${localList}" ]]; then
    lookupDomain="raw.githubusercontent.com"
  fi

  # Determine if $lookupDomain is resolvable
  if timeout 4 getent hosts "${lookupDomain}" &> /dev/null; then
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
  # This means that even though name resolution is working, the getent hosts check fails and the holddown timer keeps ticking and eventually fails
  # So we check the output of the last command and if it failed, attempt to use dig +short as a fallback
  if timeout 4 dig +short "${lookupDomain}" &> /dev/null; then
    if [[ -n "${secs:-}" ]]; then
      echo -e "${OVER}  ${TICK} DNS resolution is now available\\n"
    fi
    return 0
  elif [[ -n "${secs:-}" ]]; then
    echo -e "${OVER}  ${CROSS} DNS resolution is not available"
    exit 1
  fi

  # Determine error output message
  if pgrep pihole-FTL &> /dev/null; then
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

# Retrieve blocklist URLs and parse domains from adlist.list
gravity_DownloadBlocklists() {
  echo -e "  ${INFO} ${COL_BOLD}Neutrino emissions detected${COL_NC}..."

  # Retrieve source URLs from gravity database
  # We source only enabled adlists, sqlite3 stores boolean values as 0 (false) or 1 (true)
  mapfile -t sources <<< "$(sqlite3 "${gravityDBfile}" "SELECT address FROM vw_adlist;" 2> /dev/null)"
  mapfile -t sourceIDs <<< "$(sqlite3 "${gravityDBfile}" "SELECT id FROM vw_adlist;" 2> /dev/null)"

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
    return 1
  fi

  local url domain agent cmd_ext str target compression
  echo ""

  # Prepare new gravity database
  str="Preparing new gravity database"
  echo -ne "  ${INFO} ${str}..."
  rm "${gravityTEMPfile}" > /dev/null 2>&1
  output=$( { sqlite3 "${gravityTEMPfile}" < "${gravityDBschema}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to create new database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  target="$(mktemp -p "/tmp" --suffix=".gravity")"

  # Use compression to reduce the amount of data that is transfered
  # between the Pi-hole and the ad list provider. Use this feature
  # only if it is supported by the locally available version of curl
  if curl -V | grep -q "Features:.* libz"; then
    compression="--compressed"
    echo -e "  ${INFO} Using libz compression\n"
  else
      compression=""
      echo -e "  ${INFO} Libz compression not available\n"
    fi
  # Loop through $sources and download each one
  for ((i = 0; i < "${#sources[@]}"; i++)); do
    url="${sources[$i]}"
    domain="${sourceDomains[$i]}"
    id="${sourceIDs[$i]}"

    # Save the file as list.#.domain
    saveLocation="${piholeDir}/list.${id}.${domain}.${domainsExtension}"
    activeDomains[$i]="${saveLocation}"

    # Default user-agent (for Cloudflare's Browser Integrity Check: https://support.cloudflare.com/hc/en-us/articles/200170086-What-does-the-Browser-Integrity-Check-do-)
    agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36"

    # Provide special commands for blocklists which may need them
    case "${domain}" in
      "pgl.yoyo.org") cmd_ext="-d mimetype=plaintext -d hostformat=hosts";;
      *) cmd_ext="";;
    esac

    echo -e "  ${INFO} Target: ${url}"
    local regex check_url
    # Check for characters NOT allowed in URLs
    regex="[^a-zA-Z0-9:/?&%=~._()-;]"

    # this will remove first @ that is after schema and before domain
    # \1 is optional schema, \2 is userinfo
    check_url="$( sed -re 's#([^:/]*://)?([^/]+)@#\1\2#' <<< "$url" )"

    if [[ "${check_url}" =~ ${regex} ]]; then
        echo -e "  ${CROSS} Invalid Target"
    else
       gravity_DownloadBlocklistFromUrl "${url}" "${cmd_ext}" "${agent}" "${sourceIDs[$i]}" "${saveLocation}" "${target}" "${compression}"
    fi
    echo ""
  done

  str="Storing downloaded domains in new gravity database"
  echo -ne "  ${INFO} ${str}..."
  output=$( { printf ".timeout 30000\\n.mode csv\\n.import \"%s\" gravity\\n" "${target}" | sqlite3 "${gravityTEMPfile}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to fill gravity table in database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  if [[ "${status}" -eq 0 && -n "${output}" ]]; then
    echo -e "  Encountered non-critical SQL warnings. Please check the suitability of the lists you're using!\\n\\n  SQL warnings:"
    local warning file line lineno
    while IFS= read -r line; do
      echo "  - ${line}"
      warning="$(grep -oh "^[^:]*:[0-9]*" <<< "${line}")"
      file="${warning%:*}"
      lineno="${warning#*:}"
      if [[ -n "${file}" && -n "${lineno}" ]]; then
        echo -n "    Line contains: "
        awk "NR==${lineno}" < "${file}"
      fi
    done <<< "${output}"
    echo ""
  fi

  rm "${target}" > /dev/null 2>&1 || \
    echo -e "  ${CROSS} Unable to remove ${target}"

  gravity_Blackbody=true
}

total_num=0
parseList() {
  local adlistID="${1}" src="${2}" target="${3}" incorrect_lines
  # This sed does the following things:
  # 1. Remove all domains containing invalid characters. Valid are: a-z, A-Z, 0-9, dot (.), minus (-), underscore (_)
  # 2. Append ,adlistID to every line
  # 3. Ensures there is a newline on the last line
  sed -e "/[^a-zA-Z0-9.\_-]/d;s/$/,${adlistID}/;/.$/a\\" "${src}" >> "${target}"
  # Find (up to) five domains containing invalid characters (see above)
  incorrect_lines="$(sed -e "/[^a-zA-Z0-9.\_-]/!d" "${src}" | head -n 5)"

  local num_lines num_target_lines num_correct_lines num_invalid
  # Get number of lines in source file
  num_lines="$(grep -c "^" "${src}")"
  # Get number of lines in destination file
  num_target_lines="$(grep -c "^" "${target}")"
  num_correct_lines="$(( num_target_lines-total_num ))"
  total_num="$num_target_lines"
  num_invalid="$(( num_lines-num_correct_lines ))"
  if [[ "${num_invalid}" -eq 0 ]]; then
    echo "  ${INFO} Received ${num_lines} domains"
  else
    echo "  ${INFO} Received ${num_lines} domains, ${num_invalid} domains invalid!"
  fi

  # Display sample of invalid lines if we found some
  if [[ -n "${incorrect_lines}" ]]; then
    echo "      Sample of invalid domains:"
    while IFS= read -r line; do
      echo "      - ${line}"
    done <<< "${incorrect_lines}"
  fi
}

# Download specified URL and perform checks on HTTP status and file content
gravity_DownloadBlocklistFromUrl() {
  local url="${1}" cmd_ext="${2}" agent="${3}" adlistID="${4}" saveLocation="${5}" target="${6}" compression="${7}"
  local heisenbergCompensator="" patternBuffer str httpCode success=""

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
    ip=$(dig "@${ip_addr}" -p "${port}" +short "${domain}" | tail -1)
    if [[ $(echo "${url}" | awk -F '://' '{print $1}') = "https" ]]; then
      port=443;
    else port=80
    fi
    bad_list=$(pihole -q -adlist "${domain}" | head -n1 | awk -F 'Match found in ' '{print $2}')
    echo -e "${OVER}  ${CROSS} ${str} ${domain} is blocked by ${bad_list%:}. Using DNS on ${PIHOLE_DNS_1} to download ${url}";
    echo -ne "  ${INFO} ${str} Pending..."
    cmd_ext="--resolve $domain:$port:$ip $cmd_ext"
  fi

  # shellcheck disable=SC2086
  httpCode=$(curl -s -L ${compression} ${cmd_ext} ${heisenbergCompensator} -w "%{http_code}" -A "${agent}" "${url}" -o "${patternBuffer}" 2> /dev/null)

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
      # Add domains to database table file
      parseList "${adlistID}" "${saveLocation}" "${target}"
    # Check if $patternbuffer is a non-zero length file
    elif [[ -s "${patternBuffer}" ]]; then
      # Determine if blocklist is non-standard and parse as appropriate
      gravity_ParseFileIntoDomains "${patternBuffer}" "${saveLocation}"
      # Add domains to database table file
      parseList "${adlistID}" "${saveLocation}" "${target}"
      # Update date_updated field in gravity database table
      database_adlist_updated "${adlistID}"
    else
      # Fall back to previously cached list if $patternBuffer is empty
      echo -e "  ${INFO} Received empty file: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
    fi
  else
    # Determine if cached list has read permission
    if [[ -r "${saveLocation}" ]]; then
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_GREEN}using previously cached list${COL_NC}"
      # Add domains to database table file
      parseList "${adlistID}" "${saveLocation}" "${target}"
    else
      echo -e "  ${CROSS} List download failed: ${COL_LIGHT_RED}no cached list available${COL_NC}"
    fi
  fi
}

# Parse source files into domains format
gravity_ParseFileIntoDomains() {
  local source="${1}" destination="${2}" firstLine

  # Determine if we are parsing a consolidated list
  #if [[ "${source}" == "${piholeDir}/${matterAndLight}" ]]; then
    # Remove comments and print only the domain name
    # Most of the lists downloaded are already in hosts file format but the spacing/formating is not contiguous
    # This helps with that and makes it easier to read
    # It also helps with debugging so each stage of the script can be researched more in depth
    # 1) Remove carriage returns
    # 2) Convert all characters to lowercase
    # 3) Remove comments (text starting with "#", include possible spaces before the hash sign)
    # 4) Remove lines containing "/"
    # 5) Remove leading tabs, spaces, etc.
    # 6) Delete lines not matching domain names
    < "${source}" tr -d '\r' | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/\s*#.*//g' | \
    sed -r '/(\/).*$/d' | \
    sed -r 's/^.*\s+//g' | \
    sed -r '/([^\.]+\.)+[^\.]{2,}/!d' >  "${destination}"
    chmod 644 "${destination}"
    return 0
  #fi

  # Individual file parsing: Keep comments, while parsing domains from each line
  # We keep comments to respect the list maintainer's licensing
  read -r firstLine < "${source}"

  # Determine how to parse individual source file formats
  if [[ "${firstLine,,}" =~ (adblock|ublock|^!) ]]; then
    # Compare $firstLine against lower case words found in Adblock lists
    echo -e "  ${CROSS} Format: Adblock (list type not supported)"
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
    chmod 644 "${destination}"

    echo -e "${OVER}  ${TICK} Format: URL"
  else
    # Default: Keep hosts/domains file in same format as it was downloaded
    output=$( { mv "${source}" "${destination}"; } 2>&1 )
    chmod 644 "${destination}"

    if [[ ! -e "${destination}" ]]; then
      echo -e "\\n  ${CROSS} Unable to move tmp file to ${piholeDir}
    ${output}"
      gravity_Cleanup "error"
    fi
  fi
}

# Report number of entries in a table
gravity_Table_Count() {
  local table="${1}"
  local str="${2}"
  local num
  num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM ${table};")"
  if [[ "${table}" == "vw_gravity" ]]; then
    local unique
    unique="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(DISTINCT domain) FROM ${table};")"
    echo -e "  ${INFO} Number of ${str}: ${num} (${COL_BOLD}${unique} unique domains${COL_NC})"
    sqlite3 "${gravityDBfile}" "INSERT OR REPLACE INTO info (property,value) VALUES ('gravity_count',${unique});"
  else
    echo -e "  ${INFO} Number of ${str}: ${num}"
  fi
}

# Output count of blacklisted domains and regex filters
gravity_ShowCount() {
  gravity_Table_Count "vw_gravity" "gravity domains" ""
  gravity_Table_Count "vw_blacklist" "exact blacklisted domains"
  gravity_Table_Count "vw_regex_blacklist" "regex blacklist filters"
  gravity_Table_Count "vw_whitelist" "exact whitelisted domains"
  gravity_Table_Count "vw_regex_whitelist" "regex whitelist filters"
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
  chmod 644 "${localList}"

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
    for file in "${piholeDir}"/*."${domainsExtension}"; do
      # If list is not in active array, then remove it
      if [[ ! "${activeDomains[*]}" == *"${file}"* ]]; then
        rm -f "${file}" 2> /dev/null || \
          echo -e "  ${CROSS} Failed to remove ${file##*/}"
      fi
    done
  fi

  echo -e "${OVER}  ${TICK} ${str}"

  # Only restart DNS service if offline
  if ! pgrep pihole-FTL &> /dev/null; then
    "${PIHOLE_COMMAND}" restartdns
    dnsWasOffline=true
  fi

  # Print Pi-hole status if an error occurred
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
    "-r" | "--recreate" ) recreate_database=true;;
    "-h" | "--help" ) helpFunc;;
  esac
done

# Trap Ctrl-C
gravity_Trap

if [[ "${recreate_database:-}" == true ]]; then
  str="Restoring from migration backup"
  echo -ne "${INFO} ${str}..."
  rm "${gravityDBfile}"
  pushd "${piholeDir}" > /dev/null || exit
  cp migration_backup/* .
  popd > /dev/null || exit
  echo -e "${OVER}  ${TICK} ${str}"
fi

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
gravity_DownloadBlocklists

# Create local.list
gravity_generateLocalList

# Migrate rest of the data from old to new database
gravity_swap_databases

# Update gravity timestamp
update_gravity_timestamp

# Ensure proper permissions are set for the database
chown pihole:pihole "${gravityDBfile}"
chmod g+w "${piholeDir}" "${gravityDBfile}"

# Compute numbers to be displayed
gravity_ShowCount

# Determine if DNS has been restarted by this instance of gravity
if [[ -z "${dnsWasOffline:-}" ]]; then
  "${PIHOLE_COMMAND}" restartdns reload
fi

gravity_Cleanup
echo ""

"${PIHOLE_COMMAND}" status
