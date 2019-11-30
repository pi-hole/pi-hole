#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Whitelist and blacklist domains
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Globals
basename=pihole
piholeDir=/etc/"${basename}"
gravityDBfile="${piholeDir}/gravity.db"

reload=false
addmode=true
verbose=true
wildcard=false
web=false

domList=()

typeId=""

colfile="/opt/pihole/COL_TABLE"
source ${colfile}

getListnameFromTypeId() {
    if [[ "$1" == "0" ]]; then
        echo "whitelist"
    elif  [[ "$1" == "1" ]]; then
        echo "blacklist"
    elif  [[ "$1" == "2" ]]; then
        echo "regex_whitelist"
    elif  [[ "$1" == "3" ]]; then
        echo "regex_blacklist"
    fi
}

helpFunc() {
    if [[ "${typeId}" == "0" ]]; then
        param="w"
        type="whitelist"
    elif [[ "${typeId}" == "3" && "${wildcard}" == true ]]; then
        param="-wild"
        type="wildcard blacklist"
    elif [[ "${typeId}" == "3" ]]; then
        param="-regex"
        type="regex blacklist filter"
    elif [[ "${typeId}" == "2" && "${wildcard}" == true ]]; then
        param="-white-wild"
        type="wildcard whitelist"
    elif [[ "${typeId}" == "2" ]]; then
        param="-white-regex"
        type="regex whitelist filter"
    else
        param="b"
        type="blacklist"
    fi

    echo "Usage: pihole -${param} [options] <domain> <domain2 ...>
Example: 'pihole -${param} site.com', or 'pihole -${param} site1.com site2.com'
${type^} one or more domains

Options:
  -d, --delmode       Remove domain(s) from the ${type}
  -nr, --noreload     Update ${type} without reloading the DNS server
  -q, --quiet         Make output less verbose
  -h, --help          Show this help dialog
  -l, --list          Display all your ${type}listed domains
  --nuke              Removes all entries in a list"

  exit 0
}

HandleOther() {
    # Convert to lowercase
    domain="${1,,}"

    # Check validity of domain (don't check for regex entries)
    if [[ "${#domain}" -le 253 ]]; then
        if [[ ( "${typeId}" == "3" || "${typeId}" == "2" ) && "${wildcard}" == false ]]; then
            validDomain="${domain}"
        else
            validDomain=$(grep -P "^((-|_)*[a-z\\d]((-|_)*[a-z\\d])*(-|_)*)(\\.(-|_)*([a-z\\d]((-|_)*[a-z\\d])*))*$" <<< "${domain}") # Valid chars check
            validDomain=$(grep -P "^[^\\.]{1,63}(\\.[^\\.]{1,63})*$" <<< "${validDomain}") # Length of each label
        fi
    fi

    if [[ -n "${validDomain}" ]]; then
        domList=("${domList[@]}" ${validDomain})
    else
        echo -e "  ${CROSS} ${domain} is not a valid argument or domain name!"
    fi
}

ProcessDomainList() {
    for dom in "${domList[@]}"; do
        # Format domain into regex filter if requested
        if [[ "${wildcard}" == true ]]; then
            dom="(^|\\.)${dom//\./\\.}$"
        fi

        # Logic: If addmode then add to desired list and remove from the other;
        # if delmode then remove from desired list but do not add to the other
        if ${addmode}; then
            AddDomain "${dom}"
        else
            RemoveDomain "${dom}"
        fi
  done
}

AddDomain() {
    local domain num requestedListname existingTypeId existingListname
    domain="$1"

    # Is the domain in the list we want to add it to?
    num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM domainlist WHERE domain = '${domain}';")"
    requestedListname="$(getListnameFromTypeId "${typeId}")"

    if [[ "${num}" -ne 0 ]]; then
      existingTypeId="$(sqlite3 "${gravityDBfile}" "SELECT type FROM domainlist WHERE domain = '${domain}';")"
      if [[ "${existingTypeId}" == "${typeId}" ]]; then
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} ${1} already exists in ${requestedListname}, no need to add!"
        fi
      else
        existingListname="$(getListnameFromTypeId "${existingTypeId}")"
        sqlite3 "${gravityDBfile}" "UPDATE domainlist SET type = ${typeId} WHERE domain='${domain}';"
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} ${1} already exists in ${existingListname}, it has been moved to ${requestedListname}!"
        fi
      fi
      return
    fi

    # Domain not found in the table, add it!
    if [[ "${verbose}" == true ]]; then
        echo -e "  ${INFO} Adding ${domain} to the ${requestedListname}..."
    fi
    reload=true
    # Insert only the domain here. The enabled and date_added fields will be filled
    # with their default values (enabled = true, date_added = current timestamp)
    sqlite3 "${gravityDBfile}" "INSERT INTO domainlist (domain,type) VALUES ('${domain}',${typeId});"
}

RemoveDomain() {
    local domain num requestedListname
    domain="$1"

    # Is the domain in the list we want to remove it from?
    num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM domainlist WHERE domain = '${domain}' AND type = ${typeId};")"

    requestedListname="$(getListnameFromTypeId "${typeId}")"

    if [[ "${num}" -eq 0 ]]; then
      if [[ "${verbose}" == true ]]; then
          echo -e "  ${INFO} ${domain} does not exist in ${requestedListname}, no need to remove!"
      fi
      return
    fi

    # Domain found in the table, remove it!
    if [[ "${verbose}" == true ]]; then
        echo -e "  ${INFO} Removing ${domain} from the ${requestedListname}..."
    fi
    reload=true
    # Remove it from the current list
    sqlite3 "${gravityDBfile}" "DELETE FROM domainlist WHERE domain = '${domain}' AND type = ${typeId};"
}

Displaylist() {
    local count num_pipes domain enabled status nicedate requestedListname

    requestedListname="$(getListnameFromTypeId "${typeId}")"
    data="$(sqlite3 "${gravityDBfile}" "SELECT domain,enabled,date_modified FROM domainlist WHERE type = ${typeId};" 2> /dev/null)"

    if [[ -z $data ]]; then
        echo -e "Not showing empty list"
    else
        echo -e "Displaying ${requestedListname}:"
        count=1
        while IFS= read -r line
        do
            # Count number of pipes seen in this line
            # This is necessary because we can only detect the pipe separating the fields
            # from the end backwards as the domain (which is the first field) may contain
            # pipe symbols as they are perfectly valid regex filter control characters
            num_pipes="$(grep -c "^" <<< "$(grep -o "|" <<< "${line}")")"

            # Extract domain and enabled status based on the obtained number of pipe characters
            domain="$(cut -d'|' -f"-$((num_pipes-1))" <<< "${line}")"
            enabled="$(cut -d'|' -f"$((num_pipes))" <<< "${line}")"
            datemod="$(cut -d'|' -f"$((num_pipes+1))" <<< "${line}")"

            # Translate boolean status into human readable string
            if [[ "${enabled}" -eq 1 ]]; then
                status="enabled"
            else
                status="disabled"
            fi

            # Get nice representation of numerical date stored in database
            nicedate=$(date --rfc-2822 -d "@${datemod}")

            echo "  ${count}: ${domain} (${status}, last modified ${nicedate})"
            count=$((count+1))
        done <<< "${data}"
    fi
    exit 0;
}

NukeList() {
    sqlite3 "${gravityDBfile}" "DELETE FROM domainlist WHERE type = ${typeId};"
}

for var in "$@"; do
    case "${var}" in
        "-w" | "whitelist"   ) typeId=0;;
        "-b" | "blacklist"   ) typeId=1;;
        "--white-regex" | "white-regex" ) typeId=2;;
        "--white-wild" | "white-wild" ) typeId=2; wildcard=true;;
        "--wild" | "wildcard" ) typeId=3; wildcard=true;;
        "--regex" | "regex"   ) typeId=3;;
        "-nr"| "--noreload"  ) reload=false;;
        "-d" | "--delmode"   ) addmode=false;;
        "-q" | "--quiet"     ) verbose=false;;
        "-h" | "--help"      ) helpFunc;;
        "-l" | "--list"      ) Displaylist;;
        "--nuke"             ) NukeList;;
        "--web"              ) web=true;;
        *                    ) HandleOther "${var}";;
    esac
done

shift

if [[ $# = 0 ]]; then
    helpFunc
fi

ProcessDomainList

# Used on web interface
if $web; then
echo "DONE"
fi

if [[ "${reload}" != false ]]; then
    pihole restartdns reload
fi
