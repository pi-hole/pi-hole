#!/usr/bin/env bash
# shellcheck disable=SC1090

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Usage: "pihole -g"
# Compiles a list of ad-serving domains by downloading them from multiple sources
#
# This file is licensed under the EUPL. See LICENSE for details.

export LC_ALL=C

PI_HOLE_SCRIPT_DIR="/opt/pihole"
# Sourcing utils.sh for the GetFTLConfigValue function
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
. "${utilsfile}"

coltable="${PI_HOLE_SCRIPT_DIR}/COL_TABLE"
. "${coltable}"
. "/etc/.pihole/advanced/Scripts/database_migration/gravity-db.sh"

basename="pihole"
PIHOLE_COMMAND="/usr/local/bin/${basename}"
piholeDir="/etc/${basename}"

# Auxiliary directory for Gravity files
listsCacheDir="${piholeDir}/listsCache"

# Locations of legacy files (pre v5.0)
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

# Progress bar helper function
progress_bar() {
  local current=$1 total=$2
  local bar_width=40
  local progress=$(( current * bar_width / total ))
  local percent=$(( current * 100 / total ))
  local filled=$(printf "%${progress}s" | tr ' ' '#')
  local empty=$(printf "%$(( bar_width - progress ))s" | tr ' ' '-')
  printf "\r[%s%s] %d%% (%d/%d)" "$filled" "$empty" "$percent" "$current" "$total"
}

# Check if the Gravity temporary directory exists and is writable
if [ ! -d "${GRAVITY_TMPDIR}" ] || [ ! -w "${GRAVITY_TMPDIR}" ]; then
  echo -e "  ${COL_LIGHT_RED}Gravity temporary directory does not exist or is not writable, using /tmp.${COL_NC}"
  GRAVITY_TMPDIR="/tmp"
fi

gravityDBfile="${GRAVITYDB}"
gravityDBfile_default="/etc/pihole/gravity.db"
gravityTEMPfile="${gravityDBfile}_temp"
gravityDIR="$(dirname -- "${gravityDBfile}")"
gravityOLDfile="${gravityDIR}/gravity_old.db"
gravityBCKdir="${gravityDIR}/gravity_backups"
gravityBCKfile="${gravityBCKdir}/gravity.db"

fix_owner_permissions() {
  chown pihole:pihole "${1}"
  chmod 664 "${1}"
  chmod g+w "$(dirname -- "${1}")"
}

generate_gravity_database() {
  if ! pihole-FTL sqlite3 -ni "${gravityDBfile}" <"${gravityDBschema}"; then
    echo -e "   ${CROSS} Unable to create ${gravityDBfile}"
    return 1
  fi
  fix_owner_permissions "${gravityDBfile}"
}

gravity_build_tree() {
  local str="Building tree"
  echo -ne "  ${INFO} ${str}..."
  output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "CREATE INDEX idx_gravity ON gravity (domain, adlist_id);"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to build the tree in ${gravityTEMPfile}\\n  ${output}"
    echo -e "  ${INFO} If you have many entries, please ensure there is enough RAM."
    return 1
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

rotate_gravity_backup() {
  for i in {9..1}; do
    if [ -f "${gravityBCKfile}.${i}" ]; then
      mv "${gravityBCKfile}.${i}" "${gravityBCKfile}.$((i + 1))"
    fi
  done
}

gravity_swap_databases() {
  local str="Swapping databases"
  echo -ne "  ${INFO} ${str}..."
  availableBlocks=$(stat -f --format "%a" "${gravityDIR}")
  gravityBlocks=$(stat --format "%b" "${gravityDBfile}")
  oldAvail=false
  if [ "${availableBlocks}" -gt "$((gravityBlocks * 2))" ] && [ -f "${gravityDBfile}" ]; then
    oldAvail=true
    cp "${gravityDBfile}" "${gravityOLDfile}"
  fi
  output=$({ printf ".timeout 30000\\nDROP TABLE IF EXISTS gravity;\\nDROP TABLE IF EXISTS antigravity;\\nVACUUM;\\n" | pihole-FTL sqlite3 -ni "${gravityDBfile}"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Failed to clear the current database for backup\\n  ${output}"
  else
    if [ ! -d "${gravityBCKdir}" ]; then
      mkdir -p "${gravityBCKdir}"
    fi
    rotate_gravity_backup
    mv "${gravityDBfile}" "${gravityBCKfile}.1"
  fi
  mv "${gravityTEMPfile}" "${gravityDBfile}"
  echo -e "${OVER}  ${TICK} ${str}"
  if $oldAvail; then
    echo -e "  ${TICK} The old database remains available"
  fi
}

update_gravity_timestamp() {
  output=$({ printf ".timeout 30000\\nINSERT OR REPLACE INTO info (property,value) values ('updated',cast(strftime('%%s', 'now') as int));" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to update the timestamp in the database ${gravityTEMPfile}\\n  ${output}"
    return 1
  fi
  return 0
}

database_table_from_file() {
  local table="${1}" src="${2}" backup_path="${piholeDir}/migration_backup"
  local backup_file="${backup_path}/$(basename "${2}")"
  tmpFile="$(mktemp -p "${GRAVITY_TMPDIR}")"
  mv "${tmpFile}" "${tmpFile%.*}.gravity"
  tmpFile="${tmpFile%.*}.gravity"
  local timestamp rowid
  timestamp="$(date --utc +'%s')"
  declare -i rowid=1
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
  if [[ "${table}" == "domainlist" ]]; then
    rowid="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT MAX(id) FROM domainlist;")"
    if [[ -z "$rowid" ]]; then rowid=0; fi
    rowid+=1
  fi
  grep -v '^ *#' <"${src}" | while IFS= read -r domain; do
    if [[ -n "${domain}" ]]; then
      if [[ "${table}" == "adlist" ]]; then
        echo "${rowid},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${src}\",,0,0,0,0,0" >>"${tmpFile}"
      else
        echo "${rowid},${list_type},\"${domain}\",1,${timestamp},${timestamp},\"Migrated from ${src}\"" >>"${tmpFile}"
      fi
      rowid+=1
    fi
  done
  output=$({ printf ".timeout 30000\\n.mode csv\\n.import \"%s\" %s\\n" "${tmpFile}" "${table}" | pihole-FTL sqlite3 -ni "${gravityDBfile}"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Failed to populate table ${table}${list_type} in database ${gravityDBfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
  mkdir -p "${backup_path}"
  mv "${src}" "${backup_file}" 2>/dev/null || echo -e "  ${CROSS} Failed to backup ${src} to ${backup_path}"
  rm "${tmpFile}" >/dev/null 2>&1 || echo -e "  ${CROSS} Failed to remove temporary file ${tmpFile}"
}

gravity_column_exists() {
  output=$({ printf ".timeout 30000\\nSELECT EXISTS(SELECT * FROM pragma_table_info('%s') WHERE name='%s');\\n" "${1}" "${2}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  if [[ "${output}" == "1" ]]; then
    return 0
  fi
  return 1
}

database_adlist_number() {
  if ! gravity_column_exists "adlist" "number"; then
    return
  fi
  output=$({ printf ".timeout 30000\\nUPDATE adlist SET number = %i, invalid_domains = %i WHERE id = %i;\\n" "${2}" "${3}" "${1}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Failed to update domain count for adlist with ID ${1} in database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

database_adlist_status() {
  if ! gravity_column_exists "adlist" "status"; then
    return
  fi
  output=$({ printf ".timeout 30000\\nUPDATE adlist SET status = %i WHERE id = %i;\\n" "${2}" "${1}" | pihole-FTL sqlite3 -ni "${gravityTEMPfile}"; } 2>&1)
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Failed to update status for adlist with ID ${1} in database ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  fi
}

migrate_to_database() {
  if [ ! -e "${gravityDBfile}" ]; then
    echo -e "  ${INFO} Creating new Gravity database"
    if ! generate_gravity_database; then
      echo -e "   ${CROSS} Error creating new Gravity database. Please contact support."
      return 1
    fi
    upgrade_gravityDB "${gravityDBfile}" "${piholeDir}"
    if [ -e "${adListFile}" ]; then
      echo -e "  ${INFO} Migrating content from ${adListFile} to the new database"
      database_table_from_file "adlist" "${adListFile}"
    fi
    if [ -e "${blacklistFile}" ]; then
      echo -e "  ${INFO} Migrating content from ${blacklistFile} to the new database"
      database_table_from_file "blacklist" "${blacklistFile}"
    fi
    if [ -e "${whitelistFile}" ]; then
      echo -e "  ${INFO} Migrating content from ${whitelistFile} to the new database"
      database_table_from_file "whitelist" "${whitelistFile}"
    fi
    if [ -e "${regexFile}" ]; then
      echo -e "  ${INFO} Migrating content from ${regexFile} to the new database"
      database_table_from_file "regex" "${regexFile}"
    fi
  fi
  upgrade_gravityDB "${gravityDBfile}" "${piholeDir}"
}

gravity_CheckDNSResolutionAvailable() {
  local lookupDomain="raw.githubusercontent.com"
  if timeout 4 getent hosts "${lookupDomain}" &>/dev/null; then
    echo -e "${OVER}  ${TICK} DNS resolution available\\n"
    return 0
  else
    echo -e "  ${CROSS} DNS resolution unavailable"
  fi
  local str="Waiting for DNS resolution"
  echo -ne "  ${INFO} ${str}"
  until getent hosts github.com &> /dev/null; do
    str="${str}."
    echo -ne "  ${OVER}  ${INFO} ${str}"
    sleep 1
  done
  echo -e "${OVER}  ${TICK} DNS resolution available"
}

try_restore_backup () {
  local num="$1" filename timestamp
  filename="${gravityBCKfile}.${num}"
  if [ -f "${filename}" ]; then
    echo -e "  ${INFO} Attempting to restore backup number ${num}"
    cp "${filename}" "${gravityDBfile}"
    if [ -f "${gravityDBfile}" ]; then
      output=$({ pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <<<"${copyGravity}"; } 2>&1)
      status="$?"
      if [[ "${status}" -ne 0 ]]; then
        echo -e "\\n  ${CROSS} Failed to copy data from ${gravityDBfile} to ${gravityTEMPfile}\\n  ${output}"
        gravity_Cleanup "error"
      fi
      timestamp=$(date -r "${filename}" "+%Y-%m-%d %H:%M:%S %Z")
      pihole-FTL sqlite3 "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) values ('gravity_restored','${timestamp}');"
      echo -e "  ${TICK} Successfully restored from backup (${gravityBCKfile}.${num} dated ${timestamp})"
      return 0
    else
      echo -e "  ${CROSS} Failed to restore backup number ${num}"
    fi
  fi
  echo -e "  ${CROSS} Backup number ${num} not available"
  return 1
}

# ------------------------------------------------------------
# AUXILIARY FUNCTION: Download to a temporary file (without SQLite access)
# ------------------------------------------------------------
gravity_DownloadBlocklistToFile() {
  local url="$1" outfile="$2" compression="$3" domain="$4"
  local modifiedOptions="" httpCode success cmd_ext
  if [[ $url != file* ]]; then
    if [[ "${etag_support}" == true ]]; then
      modifiedOptions="--etag-save ${outfile}.etag"
      if [[ -f "${outfile}.etag" ]]; then
        modifiedOptions="${modifiedOptions} --etag-compare ${outfile}.etag"
      fi
    fi
    if [[ -f "${outfile}" ]]; then
      modifiedOptions="${modifiedOptions} -z ${outfile}"
    fi
  fi
  if [[ $url == file://* ]]; then
    local file_path
    file_path=$(echo "$url" | cut -d'/' -f3-)
    if [[ ! -f $file_path ]]; then
      echo -e "${OVER} ${CROSS} ${file_path} does not exist" >&2
      return 1
    fi
    cp "$file_path" "$outfile"
    success=true
  else
    httpCode=$(curl --connect-timeout ${curl_connect_timeout} -s -L ${compression} ${modifiedOptions} \
      -w "%{http_code}" "${url}" -o "${outfile}")
    case "$httpCode" in
      200|304)
        success=true
        ;;
      *)
        echo -e "${OVER} ${CROSS} Failed to download ${url} (HTTP code: ${httpCode})" >&2
        success=false
        ;;
    esac
  fi
  return 0
}

# ------------------------------------------------------------
# MAIN FUNCTION: Parallel downloads, parallel parsing, and sequential SQLite insertion
# ------------------------------------------------------------
gravity_DownloadBlocklists() {
  echo -e "  ${INFO} ${COL_BOLD}Neutrino emissions detected${COL_NC}..."
  if [[ "${gravityDBfile}" != "${gravityDBfile_default}" ]]; then
    echo -e "  ${INFO} Storing Gravity database at ${COL_BOLD}${gravityDBfile}${COL_NC}"
  fi

  # Step 1: Prepare the new database
  local str output status
  str="Preparing new Gravity database"
  echo -ne "  ${INFO} ${str}..."
  rm "${gravityTEMPfile}" >/dev/null 2>&1
  output=$( { pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <"${gravityDBschema}"; } 2>&1 )
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Unable to create ${gravityTEMPfile}\\n  ${output}"
    gravity_Cleanup "error"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  str="Creating new Gravity database copies"
  echo -ne "  ${INFO} ${str}..."
  copyGravity=$(cat "${gravityDBcopy}")
  if [[ "${gravityDBfile}" != "${gravityDBfile_default}" ]]; then
    copyGravity="${copyGravity//"${gravityDBfile_default}"/"${gravityDBfile}"}"
  fi
  output=$( { pihole-FTL sqlite3 -ni "${gravityTEMPfile}" <<<"${copyGravity}"; } 2>&1 )
  status="$?"
  if [[ "${status}" -ne 0 ]]; then
    echo -e "\\n  ${CROSS} Failed to copy data from ${gravityDBfile} to ${gravityTEMPfile}\\n  ${output}"
    local success=false
    if [[ -d "${gravityBCKdir}" ]]; then
      for i in {1..10}; do
        if try_restore_backup "${i}"; then
          success=true
          break
        fi
      done
    fi
    if [[ "${success}" == false ]]; then
      pihole-FTL sqlite3 "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) values ('gravity_restored','failed');"
      return 1
    fi
    echo -e "  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${TICK} ${str}"
  fi

  # Retrieve URLs, IDs, types, and domains from sources
  mapfile -t sources <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT address FROM vw_adlist;" 2>/dev/null)"
  mapfile -t sourceIDs <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT id FROM vw_adlist;" 2>/dev/null)"
  mapfile -t sourceTypes <<<"$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "SELECT type FROM vw_adlist;" 2>/dev/null)"
  mapfile -t sourceDomains <<<"$(
    awk -F '[/:]' '{
      gsub(/(.*:\/\/|.*:.*@)/, "", $0);
      if(length($1)>0){print $1} else {print "local"}
    }' <<<"$(printf '%s\n' "${sources[@]}")"
  )"
  local str="Retrieving source list"
  echo -e "${OVER}  ${TICK} ${str}"
  if [[ -z "${sources[*]}" ]] || [[ -z "${sourceDomains[*]}" ]]; then
    echo -e "  ${INFO} Source list is empty or not found"
    echo ""
    unset sources
  fi

  if curl -V | grep -q "Features:.* libz"; then
    compression="--compressed"
    echo -e "  ${INFO} Using libz compression\n"
  else
    compression=""
    echo -e "  ${INFO} libz compression not available\n"
  fi

  if curl --help all | grep -q "etag-save"; then
    etag_support=true
  fi

  # Create a temporary directory for downloads
  local downloadDir="${GRAVITY_TMPDIR}/gravity_downloads"
  mkdir -p "${downloadDir}"

  # ------------------------------------------------------------
  # Step 2: Parallel Downloads with Progress Bar
  # ------------------------------------------------------------
  declare -A downloadFiles
  local total_downloads=${#sources[@]}
  local i url domain id listType tempFile
  for (( i=0; i < total_downloads; i++ )); do
    url="${sources[$i]}"
    domain="${sourceDomains[$i]}"
    id="${sourceIDs[$i]}"
    if [[ "${sourceTypes[$i]}" -eq "0" ]]; then
      listType="gravity"
    else
      listType="antigravity"
    fi
    tempFile="${downloadDir}/list.${id}.${domain}.${domainsExtension}.tmp"
    downloadFiles["$id"]="${tempFile}"
    (
      if [ ! -w "$(dirname "${tempFile}")" ]; then
        echo -e "  ${CROSS} Unable to write to $(dirname "${tempFile}")" >&2
        exit 1
      fi
      echo -e "  ${INFO} Downloading: ${url}"
      timeit gravity_DownloadBlocklistToFile "${url}" "${tempFile}" "${compression}" "${domain}"
    ) &
  done

  # Monitor download progress
  while true; do
    running=$(jobs -r | wc -l)
    completed=$(( total_downloads - running ))
    progress_bar "$completed" "$total_downloads"
    if [ "$running" -eq 0 ]; then
      break
    fi
    sleep 0.5
  done
  echo ""

  # ------------------------------------------------------------
  # Step 3: Parallel Parsing with Progress Bar and Sequential SQLite Insertion
  # ------------------------------------------------------------
  # Helper function for parallel parsing (does not perform insertion).
  process_parsing() {
    local id="$1" domain="$2" tempFile="$3" listType="$4" saveLocation="$5"
    if [[ -s "${tempFile}" ]]; then
      gravity_ParseFileIntoDomains "${tempFile}" "${saveLocation}"
      chmod 644 "${saveLocation}"
      compareLists "${id}" "${saveLocation}"
    else
      if [[ -r "${saveLocation}" ]]; then
        echo -e "  ${CROSS} Download failed for list ${id}: using cache"
        database_adlist_status "${id}" "3"
      else
        echo -e "  ${CROSS} Download failed for list ${id} and no cache is available"
        database_adlist_number "${id}" 0 0
        database_adlist_status "${id}" "4"
      fi
    fi
  }

  # Use the new AWK parser for improved performance
  gravity_ParseFileIntoDomains() {
    local src="$1" destination="$2"
    awk '
    {
      gsub(/\r/, "");
      line = tolower($0);
      sub(/\s*!.*$/, "", line);
      sub(/\s*\[.*$/, "", line);
      sub(/\s*#.*/, "", line);
      gsub(/^[ \t]+|[ \t]+$/, "", line);
      if (line != "") { print line }
    }' "$src" > "$destination"
    fix_owner_permissions "${destination}"
  }

  # Prepare associative arrays for later use
  declare -A saveLocations
  declare -A listTypes
  local total_parsing=${#downloadFiles[@]}
  for id in "${!downloadFiles[@]}"; do
    tempFile="${downloadFiles[$id]}"
    for (( i=0; i < ${#sourceIDs[@]}; i++ )); do
      if [[ "${sourceIDs[$i]}" == "$id" ]]; then
        domain="${sourceDomains[$i]}"
        if [[ "${sourceTypes[$i]}" -eq "0" ]]; then
          listType="gravity"
        else
          listType="antigravity"
        fi
        saveLocation="${listsCacheDir}/list.${id}.${domain}.${domainsExtension}"
        saveLocations["$id"]="$saveLocation"
        listTypes["$id"]="$listType"
        process_parsing "$id" "$domain" "$tempFile" "$listType" "$saveLocation" &
        break
      fi
    done
  done

  # Monitor parsing progress
  while true; do
    running=$(jobs -r | wc -l)
    completed=$(( total_parsing - running ))
    progress_bar "$completed" "$total_parsing"
    if [ "$running" -eq 0 ]; then
      break
    fi
    sleep 0.5
  done
  echo ""

  # Sequential SQLite insertion with progress updates
  local total_inserts=${#saveLocations[@]} count=0
  for id in "${!saveLocations[@]}"; do
    pihole-FTL "${listTypes[$id]}" parseList "${saveLocations[$id]}" "${gravityTEMPfile}" "${id}"
    count=$((count + 1))
    progress_bar "$count" "$total_inserts"
    sleep 0.1
  done
  echo ""

  rm -rf "${downloadDir}"
  gravity_Blackbody=true
}

compareLists() {
  local adlistID="${1}" target="${2}"
  if [[ ! -r "${target}" ]]; then
    echo "  ${CROSS} Unable to open ${target} for reading"
    return 1
  fi
  if [[ -s "${target}.sha1" ]]; then
    if ! sha1sum --check --status --strict "${target}.sha1"; then
      sha1sum "${target}" >"${target}.sha1"
      fix_owner_permissions "${target}.sha1"
      echo "  ${INFO} List updated"
      database_adlist_status "${adlistID}" "1"
    else
      echo "  ${INFO} List unchanged"
      database_adlist_status "${adlistID}" "2"
    fi
  else
    sha1sum "${target}" >"${target}.sha1"
    fix_owner_permissions "${target}.sha1"
    database_adlist_status "${adlistID}" "1"
  fi
}

gravity_Table_Count() {
  local table="${1}" str="${2}" num
  num="$(pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "SELECT COUNT(*) FROM ${table};")"
  if [[ "${table}" == "gravity" ]]; then
    local unique
    unique="$(pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "SELECT COUNT(*) FROM (SELECT DISTINCT domain FROM ${table});")"
    echo -e "  ${INFO} ${str} count: ${num} (${COL_BOLD}${unique} unique domains${COL_NC})"
    pihole-FTL sqlite3 -ni "${gravityTEMPfile}" "INSERT OR REPLACE INTO info (property,value) VALUES ('gravity_count',${unique});"
  else
    echo -e "  ${INFO} ${str} count: ${num}"
  fi
}

gravity_ShowCount() {
  gravity_Table_Count "gravity" "Gravity domains"
  gravity_Table_Count "domainlist WHERE type = 1 AND enabled = 1" "Blocked exact domains"
  gravity_Table_Count "domainlist WHERE type = 3 AND enabled = 1" "Blocked regex filters"
  gravity_Table_Count "domainlist WHERE type = 0 AND enabled = 1" "Allowed exact domains"
  gravity_Table_Count "domainlist WHERE type = 2 AND enabled = 1" "Allowed regex filters"
}

gravity_Trap() {
  trap '{ echo -e "\\n\\n  ${INFO} ${COL_LIGHT_RED}Aborted by user${COL_NC}"; gravity_Cleanup "error"; }' INT
}

gravity_Cleanup() {
  local error="${1:-}"
  local str="Cleaning up temporary files"
  echo -ne "  ${INFO} ${str}..."
  rm ${piholeDir}/pihole.*.txt 2>/dev/null
  rm ${piholeDir}/*.tmp 2>/dev/null
  rm "${GRAVITY_TMPDIR}"/*.phgpb 2>/dev/null
  rm "${GRAVITY_TMPDIR}"/*.ph-non-domains 2>/dev/null
  if [[ "${gravity_Blackbody:-}" == true ]]; then
    for file in "${piholeDir}"/*."${domainsExtension}"; do
      if [[ ! "${activeDomains[*]}" == *"${file}"* ]]; then
        rm -f "${file}" 2>/dev/null || echo -e "  ${CROSS} Failed to remove ${file##*/}"
      fi
    done
  fi
  echo -e "${OVER}  ${TICK} ${str}"
  if [[ -n "${error}" ]]; then
    "${PIHOLE_COMMAND}" status
    exit 1
  fi
}

database_recovery() {
  local result str option="${1}"
  str="Checking integrity of existing Gravity database (this may take a while)"
  echo -ne "  ${INFO} ${str}..."
  result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "PRAGMA integrity_check" 2>&1)"
  if [[ ${result} = "ok" ]]; then
    echo -e "${OVER}  ${TICK} ${str} - no errors found"
    str="Checking foreign keys of existing Gravity database (this may take a while)"
    echo -ne "  ${INFO} ${str}..."
    unset result
    result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" "PRAGMA foreign_key_check" 2>&1)"
    if [[ -z ${result} ]]; then
      echo -e "${OVER}  ${TICK} ${str} - no errors found"
      if [[ "${option}" != "force" ]]; then return; fi
    else
      echo -e "${OVER}  ${CROSS} ${str} - errors found:"
      while IFS= read -r line; do echo "  - $line"; done <<<"$result"
    fi
  else
    echo -e "${OVER}  ${CROSS} ${str} - errors found:"
    while IFS= read -r line; do echo "  - $line"; done <<<"$result"
  fi
  str="Attempting to recover existing Gravity database"
  echo -ne "  ${INFO} ${str}..."
  rm -f "${gravityDBfile}.recovered" >/dev/null 2>&1
  if result="$(pihole-FTL sqlite3 -ni "${gravityDBfile}" ".recover" | pihole-FTL sqlite3 -ni "${gravityDBfile}.recovered" 2>&1)"; then
    echo -e "${OVER}  ${TICK} ${str} - success"
    mv "${gravityDBfile}" "${gravityDBfile}.old"
    mv "${gravityDBfile}.recovered" "${gravityDBfile}"
    echo -ne " ${INFO} ${gravityDBfile} has been recovered"
    echo -ne " ${INFO} The old ${gravityDBfile} has been moved to ${gravityDBfile}.old"
  else
    echo -e "${OVER}  ${CROSS} ${str} - the following errors occurred:"
    while IFS= read -r line; do echo "  - $line"; done <<<"$result"
    echo -e "  ${CROSS} Recovery failed. Try \"pihole -r recreate\" instead."
    exit 1
  fi
  echo ""
}

gravity_optimize() {
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

timeit(){
  local start_time end_time elapsed_time ret
  start_time=$(date +%s%3N)
  "$@"
  ret=$?
  if [[ "${timed:-}" != true ]]; then return $ret; fi
  end_time=$(date +%s%3N)
  elapsed_time=$((end_time - start_time))
  printf "  %b--> took %d.%03d seconds%b\n" "${COL_BLUE}" $((elapsed_time / 1000)) $((elapsed_time % 1000)) "${COL_NC}"
  return $ret
}

migrate_to_listsCache_dir() {
  if [[ -d "${listsCacheDir}" ]]; then return; fi
  local str="Migrating list cache directory to new location"
  echo -ne "  ${INFO} ${str}..."
  mkdir -p "${listsCacheDir}"
  if mv "${piholeDir}"/list.* "${listsCacheDir}/" 2>/dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
  fi
  sed -i "s|${piholeDir}/|${listsCacheDir}/|g" "${listsCacheDir}"/*.sha1
}

helpFunc() {
  echo "Usage: pihole -g
Update domains from blocklists specified in adlists.list

Options:
  -f, --force          Force download of all specified blocklists
  -t, --timeit         Time the Gravity update process
  -h, --help           Show this help dialog"
  exit 0
}

repairSelector() {
  case "$1" in
  "recover") recover_database=true ;;
  "recreate") recreate_database=true ;;
  *)
    echo "Usage: pihole -g -r {recover,recreate}
Attempt to repair the Gravity database

Available options:
  pihole -g -r recover        Try to recover a damaged Gravity database file.
  pihole -g -r recover force  Run recovery even if no damage is detected.
  pihole -g -r recreate       Create a new Gravity database file from scratch."
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
    upgrade_gravityDB "${gravityDBfile}" "${piholeDir}"
    exit 0
    ;;
  "-h" | "--help") helpFunc ;;
  esac
done

if [[ -f "${gravityOLDfile}" ]]; then
  rm "${gravityOLDfile}"
fi

gravity_Trap

if [[ "${recreate_database:-}" == true ]]; then
  str="Recreating Gravity database from migration backup"
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

migrate_to_listsCache_dir

if ! timeit migrate_to_database; then
  echo -e "   ${CROSS} Unable to migrate to database. Please contact support."
  exit 1
fi

if [[ "${forceDelete:-}" == true ]]; then
  str="Deleting existing list cache"
  echo -ne "${INFO} ${str}..."
  rm "${listsCacheDir}/list.*" 2>/dev/null || true
  echo -e "${OVER}  ${TICK} ${str}"
fi

if ! timeit gravity_CheckDNSResolutionAvailable; then
  echo -e "   ${CROSS} Cannot complete Gravity update, DNS is unavailable. Please contact support."
  exit 1
fi

if ! gravity_DownloadBlocklists; then
  echo -e "   ${CROSS} Unable to create Gravity database. Please try again later. If the problem persists, contact support."
  exit 1
fi

update_gravity_timestamp
fix_owner_permissions "${gravityTEMPfile}"
timeit gravity_build_tree
timeit gravity_ShowCount
timeit gravity_optimize

if ! timeit gravity_swap_databases; then
  echo -e "   ${CROSS} Unable to create database. Please contact support."
  exit 1
fi

timeit gravity_Cleanup
echo ""
echo "  ${TICK} Done."
# "${PIHOLE_COMMAND}" status
