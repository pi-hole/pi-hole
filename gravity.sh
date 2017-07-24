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
source ${coltable}

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

domainsExtension="domains"
matterAndLight="${basename}.0.matterandlight.txt"
supernova="${basename}.1.supernova.txt"
preEventHorizon="list.preEventHorizon"
eventHorizon="${basename}.2.supernova.txt"
accretionDisc="${basename}.3.accretionDisc.txt"

skipDownload="false"

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

helpFunc() {
  echo "Usage: pihole -g
Update domains from blocklists specified in adlists.list

Options:
  -f, --force          Force the download of all specified blocklists
  -h, --help           Show this help dialog"
  exit 0
}

# Retrieve blocklist URLs from adlists.list
gravity_Collapse() {
  echo -e "  ${INFO} Neutrino emissions detected..."

  # Handle "adlists.list" and "adlists.default" files
  if [[ -f "${adListDefault}" ]] && [[ -f "${adListFile}" ]]; then
    # Remove superceded $adListDefault file
    rm "${adListDefault}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to remove ${adListDefault}"
  elif [[ ! -f "${adListFile}" ]]; then
    # Create "adlists.list"
    cp "${adListRepoDefault}" "${adListFile}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to copy ${adListFile##*/} from ${piholeRepo}"
  fi

  local str="Pulling blocklist source list into range"
  echo -ne "  ${INFO} ${str}..."

  # Retrieve source URLs from $adListFile
  # Logic: Remove comments, CR line endings and empty lines
  mapfile -t sources < <(awk '!/^[#@;!\[]/ {gsub(/\r$/, "", $0); if ($1) { print $1 } }' "${adListFile}" 2> /dev/null)

  # Parse source domains from $sources
  # Logic: Split by folder/port and remove URL protocol/password
  mapfile -t sourceDomains < <(
    awk -F '[/:]' '{
      gsub(/(.*:\/\/|.*:.*@)/, "", $0)
      print $1
    }' <<< "$(printf '%s\n' "${sources[@]}")" 2> /dev/null
  )

  if [[ -n "${sources[*]}" ]] || [[ -n "${sourceDomains[*]}" ]]; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    gravity_Cleanup "error"
  fi
}

# Parse source file into domains-only format
gravity_ParseFileAsDomains() {
  local source destination hostsFilter firstLine abpFilter
  source="${1}"
  destination="${2}"

  # Determine how to parse source file
  if [[ "${source}" == "${piholeDir}/${matterAndLight}" ]]; then
    # Symbols used as comments: "#;@![/"
    commentPattern="[#;@![\\/]"

    # Parse consolidated file by removing comments and hosts IP's
    # Logic: Process lines which do not begin with comments
    awk '!/^'"${commentPattern}"'/ {
      # If there are multiple words seperated by space
      if (NF>1) {
        # Remove comments (Inc. prefixed spaces/tabs)
        if ($0 ~ /'"${commentPattern}"'/) { gsub("( |	)'"${commentPattern}"'.*", "", $0) }
        # Print consecutive domains
        if ($3) {
          $1=""
          gsub("^ ", "", $0)
          print $0
        # Print single domain
        } else if ($2) {
          print $2
        }
      # Print single domain
      } else if($1) {
        print $1
      }
    }' "${source}" 2> /dev/null > "${destination}"
  else
    # Individual file parsing
    # Logic: comments are kept, and domains are extracted from each line
    read -r firstLine < "${source}"

    # Determine how to parse individual source file
    if [[ "${firstLine,,}" =~ "adblock" ]] || [[ "${firstLine,,}" =~ "ublock" ]] || [[ "${firstLine,,}" =~ "! checksum" ]]; then
      # Parse Adblock domains & comments: https://adblockplus.org/filter-cheatsheet 
      abpFilter="/^(\\[|!)|^(\\|\\|.*\\^)/"
      awk ''"${abpFilter}"' {
        # Remove valid adblock type options
        gsub(/~?(important|third-party|popup|subdocument|websocket),?/, "", $0)
        # Remove starting domain name anchor "||" and ending seperator "^$" ($ optional)
        gsub(/(\|\||\^\$?$)/, "", $0)
        # Remove lines which are only IPv4 addresses or contain "^/*"
        if ($0 ~ /(^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|[\\^\/\*])/) { $0="" }
        # Print if not empty
        if ($0) { print $0 }
      }' "${source}" 2> /dev/null > "${destination}"
      echo -e "  ${TICK} Format: Adblock"
    elif grep -q -E "^(https?://|([0-9]{1,3}\.){3}[0-9]{1,3}$)" "${source}" &> /dev/null; then
      # Parse URLs
      awk '{
        # Remove URL protocol, optional "username:password@", and ":?/;"
        if ($0 ~ /[:?\/;]/) { gsub(/(^.*:\/\/(.*:.*@)?|[:?\/;].*)/, "", $0) }
        # Remove lines which are only IPv4 addresses
        if ($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { $0="" }
        if ($0) { print $0 }
      }' "${source}" 2> /dev/null > "${destination}"
      echo -e "  ${TICK} Format: URL"
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

# Determine output based on gravity_Transport() status
gravity_AdvancedTransport() {
  local patternBuffer success error output status
  patternBuffer="${1}"
  success="${2}"
  error="${3}"

  if [[ "${success}" = true ]]; then
    if [[ "${error}" == "304" ]]; then
      : # Print no output
    # Check if the patternbuffer is a non-zero length file
    elif [[ -s "${patternBuffer}" ]]; then
      # Parse Adblock/URL format blocklists and include comments
      # HOSTS format is moved as-is
      gravity_ParseFileAsDomains "${patternBuffer}" "${saveLocation}" "1"
    else
      # Fall back to previously cached list if current $patternBuffer is empty
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
}

# Curl the specified URL with any necessary command extentions
gravity_Transport() {
  local url cmd_ext agent
  url="${1}"
  cmd_ext="${2}"
  agent="${3}"

  # Store downloaded content to temp file instead of RAM
  patternBuffer=$(mktemp)
  heisenbergCompensator=""
  if [[ -r "${saveLocation}" ]]; then
    # If domain has been saved, add file for date check to only download newer
    heisenbergCompensator="-z ${saveLocation}"
  fi

  local str="Status:"
  echo -ne "  ${INFO} ${str} Pending..."
  # shellcheck disable=SC2086
  httpCode=$(curl -s -L ${cmd_ext} ${heisenbergCompensator} -w "%{http_code}" -A "${agent}" "${url}" -o "${patternBuffer}" 2> /dev/null)

  # Determine "Status:" output based on HTTP response
  case "$httpCode" in
    "200" ) echo -e "${OVER}  ${TICK} ${str} Transport successful"; success=true;;
    "304" ) echo -e "${OVER}  ${TICK} ${str} No changes detected"; success=true;;
    "403" ) echo -e "${OVER}  ${CROSS} ${str} Forbidden"; success=false;;
    "404" ) echo -e "${OVER}  ${CROSS} ${str} Not found"; success=false;;
    "408" ) echo -e "${OVER}  ${CROSS} ${str} Time-out"; success=false;;
    "451" ) echo -e "${OVER}  ${CROSS} ${str} Unavailable For Legal Reasons"; success=false;;
    "521" ) echo -e "${OVER}  ${CROSS} ${str} Web Server Is Down (Cloudflare)"; success=false;;
    "522" ) echo -e "${OVER}  ${CROSS} ${str} Connection Timed Out (Cloudflare)"; success=false;;
    "500" ) echo -e "${OVER}  ${CROSS} ${str} Internal Server Error"; success=false;;
    *     ) echo -e "${OVER}  ${CROSS} ${str} Status $httpCode"; success=false;;
  esac

  # Output additional info if success=false
  gravity_AdvancedTransport "${patternBuffer}" "${success}" "${httpCode}"

  # Delete temp file if it has not been moved
  if [[ -f "${patternBuffer}" ]]; then
    rm "${patternBuffer}"
  fi
}

# Define User Agent and options for each blocklist
gravity_Pull() {
  local agent url domain cmd_ext str

  echo ""

  # Loop through $sources to download each one
  for ((i = 0; i < "${#sources[@]}"; i++)); do
    url="${sources[$i]}"
    domain="${sourceDomains[$i]}"

    # Save the file as list.#.domain
    saveLocation="${piholeDir}/list.${i}.${domain}.${domainsExtension}"
    activeDomains[$i]="${saveLocation}"

    agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"

    # Use a case statement to download lists that need special commands
    case "${domain}" in
      "pgl.yoyo.org") cmd_ext="-d mimetype=plaintext -d hostformat=hosts";;
      *) cmd_ext="";;
    esac

    if [[ "${skipDownload}" == false ]]; then
      str="Target: $domain (${url##*/})"
      echo -e "  ${INFO} ${str}"

      gravity_Transport "$url" "$cmd_ext" "$agent" "$str"

      echo ""
    fi
  done
}

# Consolidate domains to one list and add blacklisted domains
gravity_Schwarzschild() {
  local str lastLine

  str="Consolidating blocklists"
  echo -ne "  ${INFO} ${str}..."

  # Compile all blacklisted domains into one file and remove CRs
  truncate -s 0 "${piholeDir}/${matterAndLight}"
  for i in "${activeDomains[@]}"; do
    # Only assimilate list if it is available (download might have failed permanently)
    if [[ -r "${i}" ]]; then
      tr -d '\r' < "${i}" >> "${piholeDir}/${matterAndLight}"

      # Ensure each source blocklist has a final newline
      lastLine=$(tail -1 "${piholeDir}/${matterAndLight}")
      [[ "${#lastLine}" -gt 0 ]] && echo "" >> "${piholeDir}/${matterAndLight}"
    fi
  done

  echo -e "${OVER}  ${TICK} ${str}"
}

# Append blacklist entries to eventHorizon if they exist
gravity_Blacklist() {
  local numBlacklisted plural str

  if [[ -f "${blacklistFile}" ]]; then
    numBlacklisted=$(printf "%'.0f" "$(wc -l < "${blacklistFile}")")
    plural=; [[ "${numBlacklisted}" != "1" ]] && plural=s
    str="Exact blocked domain${plural}: $numBlacklisted"
    echo -e "  ${INFO} ${str}"
  else
    echo -e "  ${INFO} Nothing to blacklist!"
  fi
}

# Return number of wildcards in output
gravity_Wildcard() {
  local numWildcards plural

  if [[ -f "${wildcardFile}" ]]; then
    numWildcards=$(grep -c ^ "${wildcardFile}")
    if [[ -n "${IPV4_ADDRESS}" ]] && [[ -n "${IPV6_ADDRESS}" ]];then
      let numWildcards/=2
    fi
    plural=; [[ "${numWildcards}" != "1" ]] && plural=s
    echo -e "  ${INFO} Wildcard blocked domain${plural}: $numWildcards"
  else
    echo -e "  ${INFO} No wildcards used!"
  fi
}

# Prevent the domains of adlist sources from being blacklisted by other blocklists
gravity_Whitelist() {
  local plural str

  echo ""
  plural=; [[ "${#sources[*]}" != "1" ]] && plural=s
  str="Adding blocklist source${plural} to the whitelist"
  echo -ne "  ${INFO} ${str}..."

  # Create array of unique $sourceDomains
  # shellcheck disable=SC2046
  read -r -a uniqDomains <<< $(awk '{ if(!a[$1]++) { print $1 } }' <<< "$(printf '%s\n' "${sourceDomains[@]}")")

  ${WHITELIST_COMMAND} -nr -q "${uniqDomains[*]}" > /dev/null

  echo -e "${OVER}  ${TICK} ${str}"

  # Test existence of whitelist.txt
  if [[ -f "${whitelistFile}" ]]; then
    # Remove anything in whitelist.txt from the Event Horizon
    numWhitelisted=$(wc -l < "${whitelistFile}")
    plural=; [[ "${numWhitelisted}" != "1" ]] && plural=s
    local str="Whitelisting $numWhitelisted domain${plural}"
    echo -ne "  ${INFO} ${str}..."

    # Print everything from preEventHorizon into eventHorizon EXCEPT domains in whitelist.txt
    grep -F -x -v -f "${whitelistFile}" "${piholeDir}/${preEventHorizon}" > "${piholeDir}/${eventHorizon}"

    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "  ${INFO} Nothing to whitelist!"
  fi
}

# Sort and remove duplicate blacklisted domains
gravity_Unique() {
  local str numberOf

  str="Removing duplicate domains"
  echo -ne "  ${INFO} ${str}..."
  sort -u "${piholeDir}/${supernova}" > "${piholeDir}/${preEventHorizon}"
  echo -e "${OVER}  ${TICK} ${str}"

  numberOf=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
  echo -e "  ${INFO} ${COL_LIGHT_BLUE}${numberOf}${COL_NC} unique domains trapped in the Event Horizon"
}

# Parse list of domains into hosts format
gravity_ParseDomainsIntoHosts() {
  if [[ -n "${IPV4_ADDRESS}" ]] || [[ -n "${IPV6_ADDRESS}" ]]; then
    awk -v ipv4addr="$IPV4_ADDRESS" -v ipv6addr="$IPV6_ADDRESS" \
      '{sub(/\r$/,""); if(ipv4addr) { print ipv4addr" "$0; }; if(ipv6addr) { print ipv6addr" "$0; }}' >> "${2}" < "${1}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}No IP addresses found! Please run 'pihole -r' to reconfigure${COL_NC}\\n"
    gravity_Cleanup "error"
  fi
}

# Create "localhost" entries
gravity_ParseLocalDomains() {
  if [[ -f "/etc/hostname" ]]; then
    hostname=$(< "/etc/hostname")
  elif command -v hostname &> /dev/null; then
    hostname=$(hostname -f)
  else
    echo -e "  ${CROSS} Unable to determine fully qualified domain name of host"
  fi

  echo -e "${hostname}\\npi.hole" > "${localList}.tmp"

  # Copy the file over as /etc/pihole/local.list so dnsmasq can use it
  rm "${localList}" 2> /dev/null || \
    echo -e "  ${CROSS} Unable to remove ${localList}"
  gravity_ParseDomainsIntoHosts "${localList}.tmp" "${localList}"
  rm "${localList}.tmp" 2> /dev/null || \
    echo -e "  ${CROSS} Unable to remove ${localList}.tmp"
}

# Create primary blacklist entries
gravity_ParseBlacklistDomains() {
  # Create $accretionDisc
  [[ ! -f "${piholeDir}/${accretionDisc}" ]] && echo "" > "${piholeDir}/${accretionDisc}"

  gravity_ParseDomainsIntoHosts "${piholeDir}/${eventHorizon}" "${piholeDir}/${accretionDisc}"

  # Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
  output=$( { mv "${piholeDir}/${accretionDisc}" "${adList}"; } 2>&1 )
  status="$?"

  if [[ "${status}" -ne 0 ]]; then
    echo -e "  ${CROSS} Unable to move ${accretionDisc} from ${piholeDir}
  ${output}"
    gravity_Cleanup "error"
  fi
}

# Create user-added blacklist entries
gravity_ParseUserDomains() {
  if [[ -f "${blacklistFile}" ]]; then
    numBlacklisted=$(printf "%'.0f" "$(wc -l < "${blacklistFile}")")
    gravity_ParseDomainsIntoHosts "${blacklistFile}" "${blackList}.tmp"
    # Copy the file over as /etc/pihole/black.list so dnsmasq can use it
    mv "${blackList}.tmp" "${blackList}" 2> /dev/null || \
      echo -e "  ${CROSS} Unable to move ${blackList##*/}.tmp to ${piholeDir}"
  else
    echo -e "  ${INFO} Nothing to blacklist!"
  fi
}

# Parse consolidated blocklist into domains-only format
gravity_Advanced() {
  local str="Extracting domains from blocklists"
  echo -ne "  ${INFO} ${str}..."

  # Parse files as Hosts
  gravity_ParseFileAsDomains "${piholeDir}/${matterAndLight}" "${piholeDir}/${supernova}"

  numberOf=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${supernova}")")
  echo -e "${OVER}  ${TICK} ${str}
  ${INFO} ${COL_LIGHT_BLUE}${numberOf}${COL_NC} domains being pulled in by gravity"

  gravity_Unique
}

# Trap Ctrl-C
gravity_Trap() {
  trap '{ echo -e "\\n\\n  ${INFO} ${COL_LIGHT_RED}User-abort detected${COL_NC}"; gravity_Cleanup "error"; }' INT
}

# Clean up after Gravity
gravity_Cleanup() {
  local error="${1:-}"

  str="Cleaning up debris"
  echo -ne "  ${INFO} ${str}..."

  rm ${piholeDir}/pihole.*.txt 2> /dev/null
  rm ${piholeDir}/*.tmp 2> /dev/null

  # Remove any unused .domains files
  for file in ${piholeDir}/*.${domainsExtension}; do
    # If list is in active array then leave it (noop) else rm the list
    if [[ "${activeDomains[*]}" =~ ${file} ]]; then
      :
    else
      rm -f "${file}" 2> /dev/null || \
        echo -e "  ${CROSS} Failed to remove ${file##*/}"
    fi
  done

  echo -e "${OVER}  ${TICK} ${str}"
  
  [[ -n "$error" ]] && echo ""

  # Only restart DNS service if offline
  if ! pidof dnsmasq &> /dev/null; then
    "${PIHOLE_COMMAND}" restartdns
  fi

  if [[ -n "$error" ]]; then
    "${PIHOLE_COMMAND}" status
    exit 1
  fi
}

for var in "$@"; do
  case "${var}" in
    "-f" | "--force" ) forceDelete=true;;
    "-h" | "--help" ) helpFunc;;
    "-sd" | "--skip-download" ) skipDownload=true;;
    "-b" | "--blacklist-only" ) blackListOnly=true;;
    "-w" | "--wildcard" ) dnsRestart="restart";;
  esac
done

# Main Gravity Execution
gravity_Trap

# Use "force-reload" when restarting dnsmasq for Blacklists and Whitelists
[[ -z "${dnsRestart}" ]] && dnsRestart="force-reload"

if [[ "${forceDelete}" == true ]]; then
  str="Deleting exising list cache"
  echo -ne "${INFO} ${str}..."

  if rm /etc/pihole/list.* 2> /dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
  fi
fi

# If $blackListOnly is true, only run essential functions
if [[ ! "${blackListOnly}" == true ]]; then
  gravity_Collapse
  gravity_Pull

  if [[ "${skipDownload}" == false ]]; then
    gravity_Schwarzschild
    gravity_Advanced
  else
    echo -e "  ${INFO} Using cached Event Horizon list..."
    numberOf=$(printf "%'.0f" "$(wc -l < "${piholeDir}/${preEventHorizon}")")
    echo -e "  ${INFO} ${COL_LIGHT_BLUE}${numberOf}${COL_NC} unique domains trapped in the Event Horizon"
  fi

  gravity_Whitelist
fi

gravity_Blacklist
gravity_Wildcard

str="Parsing domains into hosts format"
echo -ne "  ${INFO} ${str}..."

if [[ ! "${blackListOnly}" == true ]]; then
  gravity_ParseLocalDomains
  gravity_ParseBlacklistDomains
fi

gravity_ParseUserDomains
echo -e "${OVER}  ${TICK} ${str}"

if [[ ! "${blackListOnly}" == true ]]; then
  gravity_Cleanup
fi

echo ""
"${PIHOLE_COMMAND}" restartdns "${dnsRestart}"
"${PIHOLE_COMMAND}" status
