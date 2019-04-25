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

domList=()

listType=""
listname=""
sqlitekey=""

# shellcheck source=/opt/pihole/COL_TABLE
source "/opt/pihole/COL_TABLE"


helpFunc() {
    if [[ "${listType}" == "whitelist" ]]; then
        param="w"
        type="whitelist"
    elif [[ "${listType}" == "regex" && "${wildcard}" == true ]]; then
        param="-wild"
        type="wildcard blacklist"
    elif [[ "${listType}" == "regex" ]]; then
        param="-regex"
        type="regex filter"
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

EscapeRegexp() {
    # This way we may safely insert an arbitrary
    # string in our regular expressions
    # This sed is intentionally executed in three steps to ease maintainability
    # The first sed removes any amount of leading dots
    echo "$@" | sed 's/^\.*//' | sed "s/[]\.|$(){}?+*^]/\\\\&/g" | sed "s/\\//\\\\\//g"
}

HandleOther() {
    # Convert to lowercase
    domain="${1,,}"

    # Check validity of domain (don't check for regex entries)
    if [[ "${#domain}" -le 253 ]]; then
        if [[ "${listType}" == "regex" && "${wildcard}" == false ]]; then
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
    if [[ "${listType}" == "regex" ]]; then
        # Regex filter list
        listname="regex filters"
        sqlitekey="filter"
    else
        # Whitelist / Blacklist
        listname="${listType}"
        sqlitekey="domain"
    fi

    for dom in "${domList[@]}"; do
        # Format domain into regex filter if requested
        if [[ "${wildcard}" == true ]]; then
            dom="(^|\\.)${dom//\./\\.}$"
        fi

        # Logic: If addmode then add to desired list and remove from the other; if delmode then remove from desired list but do not add to the othe
        if ${addmode}; then
            AddDomain "${dom}" "${listType}"
            if [[ ! "${listType}" == "regex" ]]; then
                RemoveDomain "${dom}" "${listAlt}"
            fi
        else
            RemoveDomain "${dom}" "${listType}"
        fi
  done
}

AddDomain() {
    local domain list num
    domain="$1"
    list="$2"

    # Is the domain in the list we want to add it to?
    num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM ${list} WHERE ${sqlitekey} = \"${domain}\";")"

    if [[ "${num}" -eq 0 ]]; then
        # Domain not found in the file, add it!
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} Adding ${1} to ${listname}..."
        fi
        reload=true
        # Add it to the list we want to add it to
        local timestamp
        timestamp="$(date --utc +'%s')"
        sqlite3 "${gravityDBfile}" "INSERT INTO ${list} (${sqlitekey},enabled,date_added) VALUES (\"${domain}\",1,${timestamp});"
    else
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} ${1} already exists in ${listname}, no need to add!"
        fi
    fi
}

RemoveDomain() {
    local domain list num
    domain="$1"
    list="$2"

    # Is the domain in the list we want to remove it from?
    num="$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM ${list} WHERE ${sqlitekey} = \"${domain}\";")"

    if [[ "${num}" -ne 0 ]]; then
        # Domain found in the file, remove it!
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} Removing ${1} from ${listname}..."
        fi
        reload=true
        # Remove it from the current list
        local timestamp
        timestamp="$(date --utc +'%s')"
        sqlite3 "${gravityDBfile}" "DELETE FROM ${list} WHERE ${sqlitekey} = \"${domain}\";"
    else
        if [[ "${verbose}" == true ]]; then
            echo -e "  ${INFO} ${1} does not exist in ${listname}, no need to remove!"
        fi
    fi
}

Displaylist() {
    local list listname count num_pipes domain enabled status

    if [[ "${listType}" == "regex" ]]; then
        listname="regex filters list"
    else
        # Whitelist / Blacklist
        listname="${listType}"
    fi
    data="$(sqlite3 "${gravityDBfile}" "SELECT * FROM ${listType};" 2> /dev/null)"

    if [[ -z $data ]]; then
        echo -e "Not showing empty ${listname}"
    else
        echo -e "Displaying ${listname}:"
        count=1
        while IFS= read -r line
        do
            # Count number of pipes seen in this line
            # This is necessary because we can only detect the pipe separating the fields
            # from the end backwards as the domain (which is the first field) may contain
            # pipe symbols as they are perfectly valid regex filter control characters
            num_pipes="$(grep -c "^" <<< "$(grep -o "|" <<< "${line}")")"

            domain="$(cut -d'|' -f"-$((num_pipes-2))" <<< "${line}")"
            enabled="$(cut -d'|' -f$((num_pipes-1)) <<< "${line}")"
            if [[ "${enabled}" -eq 1 ]]; then
                status="enabled"
            else
                status="disabled"
            fi

            echo "  ${count}: ${domain} (${status})"
            count=$((count+1))
        done <<< "${data}"
        exit 0;
    fi
}

NukeList() {
    sqlite3 "${gravityDBfile}" "DELETE FROM ${listType};"
}

for var in "$@"; do
    case "${var}" in
        "-w" | "whitelist"   ) listType="whitelist"; listAlt="blacklist";;
        "-b" | "blacklist"   ) listType="blacklist"; listAlt="whitelist";;
        "--wild" | "wildcard" ) listType="regex"; wildcard=true;;
        "--regex" | "regex"   ) listType="regex";;
        "-nr"| "--noreload"  ) reload=false;;
        "-d" | "--delmode"   ) addmode=false;;
        "-q" | "--quiet"     ) verbose=false;;
        "-h" | "--help"      ) helpFunc;;
        "-l" | "--list"      ) Displaylist;;
        "--nuke"             ) NukeList;;
        *                    ) HandleOther "${var}";;
    esac
done

shift

if [[ $# = 0 ]]; then
    helpFunc
fi

ProcessDomainList

if [[ "${reload}" != false ]]; then
    pihole restartdns reload
fi
