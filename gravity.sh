#!/usr/bin/env bash

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

PI_HOLE_SCRIPT_DIR="/opt/pihole"
# Source utils.sh for GetFTLConfigValue
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck source=./advanced/Scripts/utils.sh
. "${utilsfile}"

coltable="${PI_HOLE_SCRIPT_DIR}/COL_TABLE"
# shellcheck source=./advanced/Scripts/COL_TABLE
. "${coltable}"
# shellcheck source=./advanced/Scripts/database_migration/gravity-db.sh
. "/etc/.pihole/advanced/Scripts/database_migration/gravity-db.sh"

basename="pihole"
PIHOLE_COMMAND="/usr/local/bin/${basename}"

piholeDir="/etc/${basename}"

# Gravity aux files directory
listsCacheDir="${piholeDir}/listsCache"

# Legacy (pre v5.0) list file locations
whitelistFile="${piholeDir}/whitelist.txt"
blacklistFile="${piholeDir}/blacklist.txt"
regexFile="${piholeDir}/regex.list"
adListFile="${piholeDir}/adlists.list"

piholeGitDir="/etc/.pihole"
GRAVITYDB=$(getFTLConfigValue files.gravity)
GRAVITY_TMPDIR=$(getFTLConfigValue files.gravity_tmp)
gravityDBschema="${piholeGitDir}/advanced/Templates/gravity.db.sql"
gravityDBcopy="${piholeGitDir}/advanced/Templates/gravity_copy.sql"

domainsExtension="domains"
curl_connect_timeout=10
etag_support=false

# Check gravity temp directory
if [ ! -d "${GRAVITY_TMPDIR}" ] || [ ! -w "${GRAVITY_TMPDIR}" ]; then
  echo -e "  ${COL_RED}Gravity temporary directory does not exist or is not a writeable directory, falling back to /tmp. ${COL_NC}"
  GRAVITY_TMPDIR="/tmp"
fi

# Set this only after sourcing pihole-FTL.conf as the gravity database path may
# have changed
gravityDBfile="${GRAVITYDB}"
gravityDBfile_default="${piholeDir}/gravity.db"
gravityTEMPfile="${GRAVITYDB}_temp"
gravityDIR="$(dirname -- "${gravityDBfile}")"
gravityOLDfile="${gravityDIR}/gravity_old.db"
gravityBCKdir="${gravityDIR}/gravity_backups"
gravityBCKfile="${gravityBCKdir}/gravity.db"

fix_owner_permissions() {
  # Fix ownership and permissions for the specified file
  # User and group are set to pihole:pihole
  # Permissions are set to 664 (rw-rw-r--)
  chown pihole:pihole "${1}"
  chmod 664 "${1}"

  # Ensure the containing directory is group writable
  chmod g+w "$(dirname -- "${1}")"
}

# Generate new SQLite3 file from schema template
generate_gravity_database() {
  if ! pihole-FTL sqlite3 -ni "${gravityDBfile}" <"${gravityDBschema}"; then
    echo -e "   ${CROSS} Unable to create ${gravityDBfile}"
    return 1
  fi
  fix_owner_permissions "${gravityDBfile}"
}

# Build gravity tree
gravity_build_tree() {
  local str
  str="Building tree"
  echo -ne "  ${INFO} ${str}..."

  # The index is intentionally not UNIQUE as poor quality adlists may contain domains more than once
  output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "CREATE INDEX idx_gravity ON gravity (domain, adlist_id);"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to build gravity tree in ${gravityTEMPfile}\\n  ${output}"
    echo -e "  ${INFO} If you have a large amount of domains, make sure your Pi-hole has enough RAM available\\n"
    return 1
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

# Rotate gravity backup files
rotate_gravity_backup() {
  for i in {9..1}; do
    if [ -f "${gravityBCKfile}.${i}" ]; then
      mv "${gravityBCKfile}.${i}" "${gravityBCKfile}.$((i + 1))"
    fi
  done
}

# Copy data from old to new database file and swap them
gravity_swap_databases() {
  str="Swapping databases"
  echo -ne "  ${INFO} ${str}..."

  # Swap databases and remove or conditionally rename old database
  # Number of available blocks on disk
  # Busybox Compat: `stat` long flags unsupported
  #   -f flag is short form of --file-system.
  #   -c flag is short form of --format.
  availableBlocks=$(stat -f -c "%a" "${gravityDIR}")
  # Number of blocks, used by gravity.db
  gravityBlocks=$(stat -c "%b" "${gravityDBfile}")
  # Only keep the old database if available disk space is at least twice the size of the existing gravity.db.
  # Better be safe than sorry...
  oldAvail=false
  if [ "${availableBlocks}" -gt "$((gravityBlocks * 2))" ] && [ -f "${gravityDBfile}" ]; then
    oldAvail=true
    cp -p "${gravityDBfile}" "${gravityOLDfile}"
  fi

  # Drop the gravity and antigravity tables + subsequent VACUUM the current
  # database for compaction
  output=$({ printf ".timeout 30000\\nDROP TABLE IF EXISTS gravity;\\nDROP TABLE IF EXISTS antigravity;\\nVACUUM;\\n" | pihole-FTL sqlite3 -ni "${gravityDBfile}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to clean current database for backup\\n  ${output}"
  else
    # Check if the backup directory exists
    if [ ! -d "${gravityBCKdir}" ]; then
      mkdir -p "${gravityBCKdir}" && chown pihole:pihole "${gravityBCKdir}"
    fi

    # If multiple gravityBCKfile's are present (appended with a number), rotate them
    # We keep at most 10 backups
    rotate_gravity_backup

    # Move the old database to the backup location
    mv "${gravityDBfile}" "${gravityBCKfile}.1"
  fi


  # Move the new database to the correct location
  mv "${gravityTEMPfile}" "${gravityDBfile}"
  echo -e "${OVER}  ${TICK} ${str}"

  if $oldAvail; then
    echo -e "  ${TICK} The old database remains available"
  fi
}

# Update timestamp when the gravity table was last updated successfully
update_gravity_timestamp() {
  output=$({ printf ".timeout 30000\\nINSERT OR REPLACE INTO info (property,value) values ('updated',cast(strftime('%%s', 'now') as int));" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update gravity timestamp in database ${gravityTEMPfile}\\n  ${output}"
    return 1
  fi
  return 0
}

# Import domains from file and store them in the specified database table
database_table_from_file() {
  # Define locals
  local table src backup_path backup_file tmpFile list_type
  table="${1}"
  src="${2}"
  backup_path="${piholeDir}/migration_backup"
  backup_file="${backup_path}/$(basename "${2}")"
  # Create a temporary file. We don't use '--suffix' here because not all
  # implementations of mktemp support it, e.g. on Alpine
  tmpFile="$(mktemp -p "${GRAVITY_TMPDIR}")"
  mv "${tmpFile}" "${tmpFile%.*}.gravity"
  tmpFile="${tmpFile%.*}.gravity"

  local timestamp
  timestamp="$(date --utc +'%s')"

  local rowid
  declare -i rowid
  rowid=1

  # Special handling for domains to be imported into the common domainlist table
  if [[ "${table}" == "whitelist" ]]; then
    list_type="0"
    table="domainlist"
  elif [[ "${table}" == "blacklist" ]]; then
    list_type="1"
    table="domainlist"
  elif [[ "${table}" == "regex" ]]; then
    list_type="3"
    table="domainlist"
  fi

  # Get MAX(id) from domainlist when INSERTing into this table
  if [[ "${table}" == "domainlist" ]]; then
    rowid="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT MAX(id) FROM domainlist;")"
    if [[ -z "$rowid" ]]; then
      rowid=0
    fi
    rowid+=1
  fi

  # Loop over all domains in ${src} file
  # Read file line by line
  grep -v '^ *#' <"${src}" | while IFS= read -r domain; do
    # Only add non-empty lines
    if [[ -n "${domain}" ]]; then
      if [[ "${table}" == "adlist" ]]; then
        # Adlist table format
        echo "${rowid},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${src}\",,0,0,0,0,0" >>"${tmpFile}"
      else
        # White-, black-, and regexlist table format
        echo "${rowid},${list_type},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${src}\"" >>"${tmpFile}"
      fi
      rowid+=1
    fi
  done

  # Store domains in database table specified by ${table}
  # Use printf as .mode and .import need to be on separate lines
  # see https://unix.stackexchange.com/a/445615/83260
  output=$({ printf ".timeout 30000\\n.mode csv\\n.import \"%s\" %s\\n" "${tmpFile}" "${table}" | pihole-FTL sqlite3 -ni "${gravityDBfile}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to fill table ${table}${list_type} in database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi

  # Move source file to backup directory, create directory if not existing
  mkdir -p "${backup_path}"
  mv "${src}" "${backup_file}" 2>/dev/null ||
    echo -e "  ${CROSS} Unable to backup ${src} to ${backup_path}"

  # Delete tmpFile
  rm "${tmpFile}" >/dev/null 2>&1 ||
    echo -e "  ${CROSS} Unable to remove ${tmpFile}"
}

# Check if a column with name ${2} exists in gravity table with name ${1}
gravity_column_exists() {
  output=$({ printf ".timeout 30000\\nSELECT EXISTS(SELECT * FROM pragma_table_info('%s') WHERE name='%s');\\n" "${1}" "${2}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  if [[ "${output}" == "1" ]]; then
    return 0 # Bash 0 is success
  fi

  return 1 # Bash non-0 is failure
}

# Update number of domain on this list. We store this in the "old" database as all values in the new database will later be overwritten
database_adlist_number() {
  # Only try to set number of domains when this field exists in the gravity database
  if ! gravity_column_exists "adlist" "number"; then
    return
  fi

  output=$({ printf ".timeout 30000\\nUPDATE adlist SET number = %i, invalid_domains = %i WHERE id = %i;\\n" "${2}" "${3}" "${1}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update number of domains in adlist with ID ${1} in database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

# Update status of this list. We store this in the "old" database as all values in the new database will later be overwritten
database_adlist_status() {
  # Only try to set the status when this field exists in the gravity database
  if ! gravity_column_exists "adlist" "status"; then
    return
  fi

  output=$({ printf ".timeout 30000\\nUPDATE adlist SET status = %i WHERE id = %i;\\n" "${2}" "${1}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update status of adlist with ID ${1} in database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

# Migrate pre-v5.0 list files to database-based Pi-hole versions
migrate_to_database() {
  # Create database file only if not present
  if [ ! -e "${gravityDBfile}" ]; then
    # Create new database file - note that this will be created in version 1
    echo -e "  ${INFO} Creating new gravity database"
    if ! generate_gravity_database; then
      echo -e "   ${CROSS} Error creating new gravity database. Please contact support."
      return 1
    fi

    # Check if gravity database needs to be updated
    upgrade_gravityDB "${gravityDBfile}"

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
  upgrade_gravityDB "${gravityDBfile}"
}

# Determine if DNS resolution is available before proceeding
gravity_CheckDNSResolutionAvailable() {
  local lookupDomain="raw.githubusercontent.com"

  # Determine if $lookupDomain is resolvable
  if timeout 4 getent hosts "${lookupDomain}" &>/dev/null; then
    echo -e "${OVER}  ${TICK} DNS resolution is available\\n"
    return 0
  else
    echo -e "  ${CROSS} DNS resolution is currently unavailable"
  fi

  str="Waiting up to 120 seconds for DNS resolution..."
  echo -ne "  ${INFO} ${str}"

 # Default DNS timeout is two seconds, plus 1 second for each dot > 120 seconds
  for ((i = 0; i < 40; i++)); do
      if getent hosts github.com &> /dev/null; then
        # If we reach this point, DNS resolution is available
        echo -e "${OVER}  ${TICK} DNS resolution is available"
        return 0
      fi
      # Append one dot for each second waiting
      echo -ne "."
      sleep 1
  done

  # DNS resolution is still unavailable after 120 seconds
  return 1

}

# Function: try_restore_backup
# Description: Attempts to restore the previous Pi-hole gravity database from a
#              backup file. If a backup exists, it copies the backup to the
#              gravity database file and prepares a new gravity database. If the
#              restoration is successful, it returns 0. Otherwise, it returns 1.
# Returns:
#   0 - If the backup is successfully restored.
#   1 - If no backup is available or if the restoration fails.
try_restore_backup () {
  local num filename timestamp
  num=$1
  filename="${gravityBCKfile}.${num}"
  # Check if a backup exists
  if [ -f "${filename}" ]; then
    echo -e "  ${INFO} Attempting to restore previous database from backup no. ${num}"
    cp "${filename}" "${gravityDBfile}"

    # If the backup was successfully copied, prepare a new gravity database from
    # it
    if [ -f "${gravityDBfile}" ]; then
      output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <<<"${copyGravity}"; } 2>&1)
      status="$?"

      # Error checking
      if [[ "${status}" -ne 0 ]]; then
        echo -e "\\n  ${CROSS} Unable to copy data from ${gravityDBfile} to ${gravityTEMPfile}\\n  ${output}"
        gravity_Cleanup "error"
      fi

      # Get the timestamp of the backup file in a human-readable format
      # Note that this timestamp will be in the server timezone, this may be
      # GMT, e.g., on a Raspberry Pi where the default timezone has never been
      # changed
      timestamp=$(date -r "${filename}" "+%Y-%m-%d %H:%M:%S %Z")

      # Add a record to the info table to indicate that the gravity database was restored
      pihole-FTL sqlite3 "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) values ('gravity_restored','${timestamp}');"
      echo -e "  ${TICK} Successfully restored from backup (${gravityBCKfile}.${num} at ${timestamp})"
      return 0
    else
      echo -e "  ${CROSS} Unable to restore backup no. ${num}"
    fi
  fi

  echo -e "  ${CROSS} Backup no. ${num} not available"
  return 1
}

# Retrieve blocklist URLs and parse domains from adlist.list
gravity_DownloadBlocklists() {
  echo -e "  ${INFO} ${COL_BOLD}Neutrino emissions detected${COL_NC}..."

  if [[ "${gravityDBfile}" != "${gravityDBfile_default}" ]]; then
    echo -e "  ${INFO} Storing gravity database in ${COL_BOLD}${gravityDBfile}${COL_NC}"
  fi

  local url domain str compression adlist_type directory success
  echo ""

  # Prepare new gravity database
  str="Preparing new gravity database"
  echo -ne "  ${INFO} ${str}..."
  rm "${gravityTEMPfile}" >/dev/null 2>&1
  output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <"${gravityDBschema}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to create new database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  str="Creating new gravity databases"
  echo -ne "  ${INFO} ${str}..."

  # Gravity copying SQL script
  copyGravity="$(cat "${gravityDBcopy}")"
  if [[ "${gravityDBfile}" != "${gravityDBfile_default}" ]]; then
    # Replace default gravity script location by custom location
    copyGravity="${copyGravity//"${gravityDBfile_default}"/"${gravityDBfile}"}"
  fi

  output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <<<"${copyGravity}"; } 2>&1)
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to copy data from ${gravityDBfile} to ${gravityTEMPfile}\\n  ${output}"

    # Try to attempt a backup restore
    success=false
    if [[ -d "${gravityBCKdir}" ]]; then
      for i in {1..10}; do
        if try_restore_backup "${i}"; then
          success=true
          break
        fi
      done
    fi

    # If none of the attempts worked, return 1
    if [[ "${success}" == false ]]; then
      pihole-FTL sqlite3 "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) values ('gravity_restored','failed');"
      return 1
    fi

    echo -e "  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  # Retrieve source URLs from gravity database
  # We source only enabled adlists, SQLite3 stores boolean values as 0 (false) or 1 (true)
  mapfile -t sources <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT address FROM vw_adlist;" 2>/dev/null)"
  mapfile -t sourceIDs <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT id FROM vw_adlist;" 2>/dev/null)"
  mapfile -t sourceTypes <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT type FROM vw_adlist;" 2>/dev/null)"

  # Parse source domains from $sources
  mapfile -t sourceDomains <<<"$(
    # Logic: Split by folder/port
    awk -F '[/:]' '{
      # Remove URL protocol & optional username:password@
      gsub(/(.*:\/\/|.*:.*@)/, "", $0)
      if(length($1)>0){print $1}
      else {print "local"}
    }' <<<"$(printf '%s\n' "${sources[@]}")" 2>/dev/null
  )"

  local str="Pulling blocklist source list into range"
  echo -e "${OVER}  ${TICK} ${str}"

  if [[ -z "${sources[*]}" ]] || [[ -z "${sourceDomains[*]}" ]]; then
    echo -e "  ${INFO} No source list found, or it is empty"
    echo ""
    unset sources
  fi

  # Use compression to reduce the amount of data that is transferred
  # between the Pi-hole and the ad list provider. Use this feature
  # only if it is supported by the locally available version of curl
  if curl -V | grep -q "Features:.* libz"; then
    compression="--compressed"
    echo -e "  ${INFO} Using libz compression\n"
  else
    compression=""
    echo -e "  ${INFO} Libz compression not available\n"
  fi

  # Check if etag is supported by the locally available version of curl
  # (available as of curl 7.68.0, released Jan 2020)
  # https://github.com/curl/curl/pull/4543 +
  # https://github.com/curl/curl/pull/4678
  if curl --help all | grep -q "etag-save"; then
    etag_support=true
  fi

  # Loop through $sources and download each one
  for ((i = 0; i < "${#sources[@]}"; i++)); do
    url="${sources[$i]}"
    domain="${sourceDomains[$i]}"
    id="${sourceIDs[$i]}"
    if [[ "${sourceTypes[$i]}" -eq "0" ]]; then
      # Gravity list
      str="blocklist"
      adlist_type="gravity"
    else
      # AntiGravity list
      str="allowlist"
      adlist_type="antigravity"
    fi

    # Save the file as list.#.domain
    saveLocation="${listsCacheDir}/list.${id}.${domain}.${domainsExtension}"
    activeDomains[i]="${saveLocation}"

    # Check if we can write to the save location file without actually creating
    # it (in case it doesn't exist)
    # First, check if the directory is writable
    directory="$(dirname -- "${saveLocation}")"
    if [ ! -w "${directory}" ]; then
      echo -e "  ${CROSS} Unable to write to ${directory}"
      echo "      Please run pihole -g as root"
      echo ""
      continue
    fi
    # Then, check if the file is writable (if it exists)
    if [ -e "${saveLocation}" ] && [ ! -w "${saveLocation}" ]; then
      echo -e "  ${CROSS} Unable to write to ${saveLocation}"
      echo "      Please run pihole -g as root"
      echo ""
      continue
    fi

    echo -e "  ${INFO} Target: ${url}"
    local regex check_url
    # Check for characters NOT allowed in URLs
    regex="[^a-zA-Z0-9:/?&%=~._()-;]"

    # this will remove first @ that is after schema and before domain
    # \1 is optional schema, \2 is userinfo
    check_url="$(sed -re 's#([^:/]*://)?([^/]+)@#\1\2#' <<<"$url")"

    if [[ "${check_url}" =~ ${regex} ]]; then
      echo -e "  ${CROSS} Invalid Target"
    else
      timeit gravity_DownloadBlocklistFromUrl "${url}" "${sourceIDs[$i]}" "${saveLocation}" "${compression}" "${adlist_type}" "${domain}"
    fi
    echo ""
  done

  DownloadBlocklists_done=true
}

compareLists() {
  local adlistID="${1}" target="${2}"

  # Verify checksum when an older checksum exists
  if [[ -s "${target}.sha1" ]]; then
    if ! sha1sum --check --status --strict "${target}.sha1"; then
      # The list changed upstream, we need to update the checksum
      sha1sum "${target}" >"${target}.sha1"
      fix_owner_permissions "${target}.sha1"
      echo "  ${INFO} List has been updated"
      database_adlist_status "${adlistID}" "1"
    else
      echo "  ${INFO} List stayed unchanged"
      database_adlist_status "${adlistID}" "2"
    fi
  else
    # No checksum available, create one for comparing on the next run
    sha1sum "${target}" >"${target}.sha1"
    fix_owner_permissions "${target}.sha1"
    # We assume here it was changed upstream
    database_adlist_status "${adlistID}" "1"
  fi
}

# Download specified URL and perform checks on HTTP status and file content
gravity_DownloadBlocklistFromUrl() {
  local url="${1}" adlistID="${2}" saveLocation="${3}" compression="${4}" gravity_type="${5}" domain="${6}"
  local listCurlBuffer str httpCode success="" ip customUpstreamResolver=""
  local file_path permissions ip_addr port blocked=false download=true
  # modifiedOptions is an array to store all the options used to check if the adlist has been changed upstream
  local modifiedOptions=()

  # Create temp file to store content on disk instead of RAM
  # We don't use '--suffix' here because not all implementations of mktemp support it, e.g. on Alpine
  listCurlBuffer="$(mktemp -p "${GRAVITY_TMPDIR}")"
  mv "${listCurlBuffer}" "${listCurlBuffer%.*}.phgpb"
  listCurlBuffer="${listCurlBuffer%.*}.phgpb"

  # For all remote files, we try to determine if the file has changed to skip
  # downloading them whenever possible.
  if [[ $url != "file"* ]]; then
    # Use the HTTP ETag header to determine if the file has changed if supported
    # by curl. Using ETags is supported by raw.githubusercontent.com URLs.
    if [[ "${etag_support}" == true ]]; then
      # Save HTTP ETag to the specified file. An ETag is a caching related header,
      # usually returned in a response. If no ETag is sent by the server, an empty
      # file is created and can later be used consistently.
      modifiedOptions=("${modifiedOptions[@]}" --etag-save "${saveLocation}".etag)

      if [[ -f "${saveLocation}.etag" ]]; then
        # This option makes a conditional HTTP request for the specific ETag read
        # from the given file by sending a custom If-None-Match header using the
        # stored ETag. This way, the server will only send the file if it has
        # changed since the last request.
        modifiedOptions=("${modifiedOptions[@]}" --etag-compare "${saveLocation}".etag)
      fi
    fi

    # Add If-Modified-Since header to the request if we did already download the
    # file once
    if [[ -f "${saveLocation}" ]]; then
      # Request a file that has been modified later than the given time and
      # date. We provide a file here which makes curl use the modification
      # timestamp (mtime) of this file.
      # Interstingly, this option is not supported by raw.githubusercontent.com
      # URLs, however, it is still supported by many older web servers which may
      # not support the HTTP ETag method so we keep it as a fallback.
      modifiedOptions=("${modifiedOptions[@]}" -z "${saveLocation}")
    fi
  fi

  str="Status:"
  echo -ne "  ${INFO} ${str} Pending..."
  blocked=false
  # Check if this domain is blocked by Pi-hole but only if the domain is not a
  # local file or empty
  if [[ $url != "file"* ]] && [[ -n "${domain}" ]]; then
    case $(getFTLConfigValue dns.blocking.mode) in
    "IP-NODATA-AAAA" | "IP")
      # Get IP address of this domain
      ip="$(dig "${domain}" +short)"
      # Check if this IP matches any IP of the system
      if [[ -n "${ip}" && $(grep -Ec "inet(|6) ${ip}" <<<"$(ip a)") -gt 0 ]]; then
        blocked=true
      fi
      ;;
    "NXDOMAIN")
      if [[ $(dig "${domain}" | grep "NXDOMAIN" -c) -ge 1 ]]; then
        blocked=true
      fi
      ;;
    "NODATA")
      if [[ $(dig "${domain}" | grep "NOERROR" -c) -ge 1 ]] && [[ -z $(dig +short "${domain}") ]]; then
        blocked=true
      fi
      ;;
    "NULL" | *)
      if [[ $(dig "${domain}" +short | grep "0.0.0.0" -c) -ge 1 ]]; then
        blocked=true
      fi
      ;;
    esac

    if [[ "${blocked}" == true ]]; then
      # Get first defined upstream server
      local upstream
      upstream="$(getFTLConfigValue dns.upstreams)"

      # Isolate first upstream server from a string like
      # [ 1.2.3.4#1234, 5.6.7.8#5678, ... ]
      upstream="${upstream%%,*}"
      upstream="${upstream##*[}"
      upstream="${upstream%%]*}"
      # Trim leading and trailing spaces and tabs
      upstream="${upstream#"${upstream%%[![:space:]]*}"}"
      upstream="${upstream%"${upstream##*[![:space:]]}"}"

      # Get IP address and port of this upstream server
      local ip_addr port
      printf -v ip_addr "%s" "${upstream%#*}"
      if [[ ${upstream} != *"#"* ]]; then
        port=53
      else
        printf -v port "%s" "${upstream#*#}"
      fi
      ip=$(dig "@${ip_addr}" -p "${port}" +short "${domain}" | tail -1)
      if [[ $(echo "${url}" | awk -F '://' '{print $1}') = "https" ]]; then
        port=443
      else
        port=80
      fi
      echo -e "${OVER}  ${CROSS} ${str} ${domain} is blocked by one of your lists. Using DNS server ${upstream} instead"
      echo -ne "  ${INFO} ${str} Pending..."
      customUpstreamResolver="--resolve $domain:$port:$ip"
    fi
  fi

  # If we are going to "download" a local file, we first check if the target
  # file has a+r permission. We explicitly check for all+read because we want
  # to make sure that the file is readable by everyone and not just the user
  # running the script.
  if [[ $url == "file://"* ]]; then
    # Get the file path
    file_path=$(echo "$url" | cut -d'/' -f3-)
    # Check if the file exists and is a regular file (i.e. not a socket, fifo, tty, block). Might still be a symlink.
    if [[ ! -f $file_path ]]; then
      # Output that the file does not exist
      echo -e "${OVER}  ${CROSS} ${file_path} does not exist"
      download=false
    else
      # Check if the file or a file referenced by the symlink has a+r permissions
      permissions=$(stat -L -c "%a" "$file_path")
      if [[ $permissions == *4 || $permissions == *5 || $permissions == *6 || $permissions == *7 ]]; then
        # Output that we are using the local file
        echo -e "${OVER}  ${INFO} Using local file ${file_path}"
      else
        # Output that the file does not have the correct permissions
        echo -e "${OVER}  ${CROSS} Cannot read file (file needs to have a+r permission)"
        download=false
      fi
    fi
  fi

  # Check for allowed protocols
  if [[ $url != "http"* && $url != "https"* && $url != "file"* && $url != "ftp"* && $url != "ftps"* && $url != "sftp"* ]]; then
    echo -e "${OVER}  ${CROSS} ${str} Invalid protocol specified. Ignoring list."
    echo -e "      Ensure your URL starts with a valid protocol like http:// , https:// or file:// ."
    download=false
  fi

  if [[ "${download}" == true ]]; then
    httpCode=$(curl --connect-timeout ${curl_connect_timeout} -s -L ${compression:+${compression}} ${customUpstreamResolver:+${customUpstreamResolver}} "${modifiedOptions[@]}" -w "%{http_code}" "${url}" -o "${listCurlBuffer}" 2>/dev/null)
  fi

  case $url in
  # Did we "download" a local file?
  "file"*)
    if [[ -s "${listCurlBuffer}" ]]; then
      echo -e "${OVER}  ${TICK} ${str} Retrieval successful"
      success=true
    else
      echo -e "${OVER}  ${CROSS} ${str} Retrieval failed / empty list"
    fi
    ;;
  # Did we "download" a remote file?
  *)
    # Determine "Status:" output based on HTTP response
    case "${httpCode}" in
    "200")
      echo -e "${OVER}  ${TICK} ${str} Retrieval successful"
      success=true
      ;;
    "304")
      echo -e "${OVER}  ${TICK} ${str} No changes detected"
      success=true
      ;;
    "000") echo -e "${OVER}  ${CROSS} ${str} Connection Refused" ;;
    "403") echo -e "${OVER}  ${CROSS} ${str} Forbidden" ;;
    "404") echo -e "${OVER}  ${CROSS} ${str} Not found" ;;
    "408") echo -e "${OVER}  ${CROSS} ${str} Time-out" ;;
    "451") echo -e "${OVER}  ${CROSS} ${str} Unavailable For Legal Reasons" ;;
    "500") echo -e "${OVER}  ${CROSS} ${str} Internal Server Error" ;;
    "504") echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Gateway)" ;;
    "521") echo -e "${OVER}  ${CROSS} ${str} Web Server Is Down (Cloudflare)" ;;
    "522") echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Cloudflare)" ;;
    *) echo -e "${OVER}  ${CROSS} ${str} ${url} (${httpCode})" ;;
    esac
    ;;
  esac

  local done="false"
  # Determine if the blocklist was downloaded and saved correctly
  if [[ "${success}" == true ]]; then
    if [[ "${httpCode}" == "304" ]]; then
      # Set list status to "unchanged/cached"
      database_adlist_status "${adlistID}" "2"
      # Add domains to database table file
      pihole-FTL "${gravity_type}" parseList "${saveLocation}" "${gravityTEMPfile}" "${adlistID}"
      done="true"
    # Check if $listCurlBuffer is a non-zero length file
    elif [[ -s "${listCurlBuffer}" ]]; then
      # Move the downloaded list to the final location
      mv "${listCurlBuffer}" "${saveLocation}"
      # Ensure the file has the correct permissions
      fix_owner_permissions "${saveLocation}"
      # Compare lists if they are identical
      compareLists "${adlistID}" "${saveLocation}"
      # Add domains to database table file
      pihole-FTL "${gravity_type}" parseList "${saveLocation}" "${gravityTEMPfile}" "${adlistID}"
      done="true"
    else
      # Fall back to previously cached list if $listCurlBuffer is empty
      echo -e "  ${INFO} Received empty file"
    fi
  fi

  # Do we need to fall back to a cached list (if available)?
  if [[ "${done}" != "true" ]]; then
    # Determine if cached list has read permission
    if [[ -r "${saveLocation}" ]]; then
      echo -e "  ${CROSS} List download failed: ${COL_GREEN}using previously cached list${COL_NC}"
      # Set list status to "download-failed/cached"
      database_adlist_status "${adlistID}" "3"
      # Add domains to database table file
      pihole-FTL "${gravity_type}" parseList "${saveLocation}" "${gravityTEMPfile}" "${adlistID}"
    else
      echo -e "  ${CROSS} List download failed: ${COL_RED}no cached list available${COL_NC}"
      # Manually reset these two numbers because we do not call parseList here
      database_adlist_number "${adlistID}" 0 0
      database_adlist_status "${adlistID}" "4"
    fi
  fi
}

# Report number of entries in a table
gravity_Table_Count() {
  local table="${1}"
  local str="${2}"
  local num
  num="$(pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "SELECT COUNT(*) FROM ${table};")"
  if [[ "${table}" == "gravity" ]]; then
    local unique
    unique="$(pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "SELECT COUNT(*) FROM (SELECT DISTINCT domain FROM ${table});")"
    echo -e "  ${INFO} Number of ${str}: ${num} (${COL_BOLD}${unique} unique domains${COL_NC})"
    pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) VALUES ('gravity_count',${unique});"
  else
    echo -e "  ${INFO} Number of ${str}: ${num}"
  fi
}

# Output count of denied and allowed domains and regex filters
gravity_ShowCount() {
  # Here we use the table "gravity" instead of the view "vw_gravity" for speed.
  # It's safe to replace it here, because right after a gravity run both will show the exactly same number of domains.
  gravity_Table_Count "gravity" "gravity domains"
  gravity_Table_Count "domainlist WHERE type = 1 AND enabled = 1" "exact denied domains"
  gravity_Table_Count "domainlist WHERE type = 3 AND enabled = 1" "regex denied filters"
  gravity_Table_Count "domainlist WHERE type = 0 AND enabled = 1" "exact allowed domains"
  gravity_Table_Count "domainlist WHERE type = 2 AND enabled = 1" "regex allowed filters"
}

# Trap Ctrl-C
gravity_Trap() {
  trap '{ echo -e "\\n\\n  ${INFO} ${COL_RED}User-abort detected${COL_NC}"; gravity_Cleanup "error"; }' INT
}

# Clean up after Gravity upon exit or cancellation
gravity_Cleanup() {
  local error="${1:-}"

  str="Cleaning up stray matter"
  echo -ne "  ${INFO} ${str}..."

  # Delete tmp content generated by Gravity
  rm ${piholeDir}/pihole.*.txt 2>/dev/null
  rm ${piholeDir}/*.tmp 2>/dev/null
  # listCurlBuffer location
  rm "${GRAVITY_TMPDIR}"/*.phgpb 2>/dev/null
  # invalid_domains location
  rm "${GRAVITY_TMPDIR}"/*.ph-non-domains 2>/dev/null

  # Ensure this function only runs when gravity_DownloadBlocklists() has completed
  if [[ "${DownloadBlocklists_done:-}" == true ]]; then
    # Remove any unused .domains/.etag/.sha files
    for file in "${listsCacheDir}"/*."${domainsExtension}"; do
      # If list is not in active array, then remove it and all associated files
      if [[ ! "${activeDomains[*]}" == *"${file}"* ]]; then
        rm -f "${file}"* 2>/dev/null ||
          echo -e "  ${CROSS} Failed to remove ${file##*/}"
      fi
    done
  fi

  echo -e "${OVER}  ${TICK} ${str}"

  # Print Pi-hole status if an error occurred
  if [[ -n "${error}" ]]; then
    "${PIHOLE_COMMAND}" status
    exit 1
  fi
}

database_recovery() {
  local result
  local str="Checking integrity of existing gravity database (this can take a while)"
  local option="${1}"
  echo -ne "  ${INFO} ${str}..."
  result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "PRAGMA integrity_check" 2>&1)"

  if [[ ${result} = "ok" ]]; then
    echo -e "${OVER}  ${TICK} ${str} - no errors found"

    str="Checking foreign keys of existing gravity database (this can take a while)"
    echo -ne "  ${INFO} ${str}..."
    unset result
    result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "PRAGMA foreign_key_check" 2>&1)"
    if [[ -z ${result} ]]; then
      echo -e "${OVER}  ${TICK} ${str} - no errors found"
      if [[ "${option}" != "force" ]]; then
        return
      fi
    else
      echo -e "${OVER}  ${CROSS} ${str} - errors found:"
      while IFS= read -r line; do echo "  - $line"; done <<<"$result"
    fi
  else
    echo -e "${OVER}  ${CROSS} ${str} - errors found:"
    while IFS= read -r line; do echo "  - $line"; done <<<"$result"
  fi

  str="Trying to recover existing gravity database"
  echo -ne "  ${INFO} ${str}..."
  # We have to remove any possibly existing recovery database or this will fail
  rm -f "${gravityDBfile}.recovered" >/dev/null 2>&1
  if result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" ".recover" | pihole-FTL sqlite3 -ni "${gravityDBfile}.recovered" 2>&1)"; then
    echo -e "${OVER}  ${TICK} ${str} - success"
    mv "${gravityDBfile}" "${gravityDBfile}.old"
    mv "${gravityDBfile}.recovered" "${gravityDBfile}"
    echo -ne " ${INFO} ${gravityDBfile} has been recovered"
    echo -ne " ${INFO} The old ${gravityDBfile} has been moved to ${gravityDBfile}.old"
  else
    echo -e "${OVER}  ${CROSS} ${str} - the following errors happened:"
    while IFS= read -r line; do echo "  - $line"; done <<<"$result"
    echo -e "  ${CROSS} Recovery failed. Try \"pihole -r recreate\" instead."
    exit 1
  fi
  echo ""
}

gravity_optimize() {
    # The ANALYZE command gathers statistics about tables and indices and stores
    # the collected information in internal tables of the database where the
    # query optimizer can access the information and use it to help make better
    # query planning choices
    local str="Optimizing database"
    echo -ne "  ${INFO} ${str}..."
    output=$( { pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "PRAGMA analysis_limit=0; ANALYZE" 2>&1; } 2>&1 )
    status="$?"

    if [[ "${status}" -ne 0 ]]; then
        echo -e "\\n  ${CROSS} Unable to optimize database ${gravityTEMPfile}\\n  ${output}"
        gravity_Cleanup "error"
    else
        echo -e "${OVER}  ${TICK} ${str}"
    fi
}

# Function: timeit
# Description: Measures the execution time of a given command.
#
# Usage:
#   timeit <command>
#
# Parameters:
#   <command> - The command to be executed and timed.
#
# Returns:
#   The exit status of the executed command.
#
# Output:
#   If the 'timed' variable is set to true, prints the elapsed time in seconds
#   with millisecond precision.
#
# Example:
#   timeit ls -l
#
timeit(){
  local start_time end_time elapsed_time ret

  # Capture the start time
  start_time=$(date +%s%3N)

  # Execute the command passed as arguments
  "$@"
  ret=$?

  if [[ "${timed:-}" != true ]]; then
    return $ret
  fi

  # Capture the end time
  end_time=$(date +%s%3N)

  # Calculate the elapsed time
  elapsed_time=$((end_time - start_time))

  # Display the elapsed time
  printf "  %b--> took %d.%03d seconds%b\n" "${COL_BLUE}" $((elapsed_time / 1000)) $((elapsed_time % 1000)) "${COL_NC}"

  return $ret
}

migrate_to_listsCache_dir() {
  # If the ${listsCacheDir} directory already exists, this has been done before
  if [[ -d "${listsCacheDir}" ]]; then
    return
  fi

  # If not, we need to migrate the old files to the new directory
  local str="Migrating the list's cache directory to new location"
  echo -ne "  ${INFO} ${str}..."
  mkdir -p "${listsCacheDir}" && chown pihole:pihole "${listsCacheDir}"

  # Move the old files to the new directory
  if mv "${piholeDir}"/list.* "${listsCacheDir}/" 2>/dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
  fi

  # Update the list's paths in the corresponding .sha1 files to the new location
  sed -i "s|${piholeDir}/|${listsCacheDir}/|g" "${listsCacheDir}"/*.sha1 2>/dev/null
}

helpFunc() {
  echo "Usage: pihole -g
Update domains from blocklists specified in adlists.list

Options:
  -f, --force          Force the download of all specified blocklists
  -t, --timeit         Time the gravity update process
  -h, --help           Show this help dialog"
  exit 0
}

repairSelector() {
  case "$1" in
  "recover") recover_database=true ;;
  "recreate") recreate_database=true ;;
  *)
    echo "Usage: pihole -g -r {recover,recreate}
Attempt to repair gravity database

Available options:
  pihole -g -r recover        Try to recover a damaged gravity database file.
                              Pi-hole tries to restore as much as possible
                              from a corrupted gravity database.

  pihole -g -r recover force  Pi-hole will run the recovery process even when
                              no damage is detected. This option is meant to be
                              a last resort. Recovery is a fragile task
                              consuming a lot of resources and shouldn't be
                              performed unnecessarily.

  pihole -g -r recreate       Create a new gravity database file from scratch.
                              This will remove your existing gravity database
                              and create a new file from scratch. If you still
                              have the migration backup created when migrating
                              to Pi-hole v5.0, Pi-hole will import these files."
    exit 0
    ;;
  esac
}

for var in "$@"; do
  case "${var}" in
  "-f" | "--force") forceDelete=true ;;
  "-t" | "--timeit") timed=true ;;
  "-r" | "--repair") repairSelector "$3" ;;
  "-u" | "--upgrade")
    upgrade_gravityDB "${gravityDBfile}"
    exit 0
    ;;
  "-h" | "--help") helpFunc ;;
  esac
done

# Check if DNS is available, no need to do any database manipulation if we're not able to download adlists
if ! timeit gravity_CheckDNSResolutionAvailable; then
  echo -e "   ${CROSS} No DNS resolution available. Please contact support."
  exit 1
fi

# Remove OLD (backup) gravity file, if it exists
if [[ -f "${gravityOLDfile}" ]]; then
  rm "${gravityOLDfile}"
fi

# Trap Ctrl-C
gravity_Trap

if [[ "${recreate_database:-}" == true ]]; then
  str="Recreating gravity database from migration backup"
  echo -ne "${INFO} ${str}..."
  rm "${gravityDBfile}"
  pushd "${piholeDir}" >/dev/null || exit
  cp migration_backup/* .
  popd >/dev/null || exit
  echo -e "${OVER}  ${TICK} ${str}"
fi

if [[ "${recover_database:-}" == true ]]; then
  timeit database_recovery "$4"
fi

# Migrate scattered list files to the new cache directory
migrate_to_listsCache_dir

# Move possibly existing legacy files to the gravity database
if ! timeit migrate_to_database; then
  echo -e "   ${CROSS} Unable to migrate to database. Please contact support."
  exit 1
fi

if [[ "${forceDelete:-}" == true ]]; then
  str="Deleting existing list cache"
  echo -ne "  ${INFO} ${str}..."

  rm "${listsCacheDir}/list.*" 2>/dev/null || true
  echo -e "${OVER}  ${TICK} ${str}"
fi

# Gravity downloads blocklists next
if ! gravity_DownloadBlocklists; then
  echo -e "   ${CROSS} Unable to create gravity database. Please try again later. If the problem persists, please contact support."
  exit 1
fi

# Update gravity timestamp
update_gravity_timestamp

# Ensure proper permissions are set for the database
fix_owner_permissions "${gravityTEMPfile}"

# Build the tree
timeit gravity_build_tree

# Compute numbers to be displayed (do this after building the tree to get the
# numbers quickly from the tree instead of having to scan the whole database)
timeit gravity_ShowCount

# Optimize the database
timeit gravity_optimize

# Migrate rest of the data from old to new database
# IMPORTANT: Swapping the databases must be the last step before the cleanup
if ! timeit gravity_swap_databases; then
  echo -e "   ${CROSS} Unable to create database. Please contact support."
  exit 1
fi

timeit gravity_Cleanup
echo ""

echo "  ${TICK} Done."

# "${PIHOLE_COMMAND}" status
