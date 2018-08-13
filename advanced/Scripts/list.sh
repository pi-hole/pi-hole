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
whitelist="${piholeDir}"/whitelist.txt
blacklist="${piholeDir}"/blacklist.txt

readonly regexlist="/etc/pihole/regex.list"
reload=false
addmode=true
verbose=true
wildcard=false

domList=()

listMain=""
listAlt=""

colfile="/opt/pihole/COL_TABLE"
source ${colfile}


helpFunc() {
    if [[ "${listMain}" == "${whitelist}" ]]; then
        param="w"
        type="white"
    elif [[ "${listMain}" == "${regexlist}" && "${wildcard}" == true ]]; then
        param="-wild"
        type="wildcard black"
    elif [[ "${listMain}" == "${regexlist}" ]]; then
        param="-regex"
        type="regex black"
    else
        param="b"
        type="black"
    fi

    echo "Usage: pihole -${param} [options] <domain> <domain2 ...>
Example: 'pihole -${param} site.com', or 'pihole -${param} site1.com site2.com'
${type^}list one or more domains

Options:
  -d, --delmode       Remove domain(s) from the ${type}list
  -nr, --noreload     Update ${type}list without refreshing dnsmasq
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
    echo $* | sed 's/^\.*//' | sed "s/[]\.|$(){}?+*^]/\\\\&/g" | sed "s/\\//\\\\\//g"
}

HandleOther() {
    # Convert to lowercase
    domain="${1,,}"

    # Check validity of domain (don't check for regex entries)
    if [[ "${#domain}" -le 253 ]]; then
        if [[ "${listMain}" == "${regexlist}" && "${wildcard}" == false ]]; then
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

PoplistFile() {
    # Check whitelist file exists, and if not, create it
    if [[ ! -f "${whitelist}" ]]; then
        touch "${whitelist}"
    fi

    # Check blacklist file exists, and if not, create it
    if [[ ! -f "${blacklist}" ]]; then
        touch "${blacklist}"
    fi

    for dom in "${domList[@]}"; do
        # Logic: If addmode then add to desired list and remove from the other; if delmode then remove from desired list but do not add to the other
        if ${addmode}; then
            AddDomain "${dom}" "${listMain}"
            RemoveDomain "${dom}" "${listAlt}"
        else
            RemoveDomain "${dom}" "${listMain}"
        fi
  done
}

AddDomain() {
    list="$2"
    domain=$(EscapeRegexp "$1")

    [[ "${list}" == "${whitelist}" ]] && listname="whitelist"
    [[ "${list}" == "${blacklist}" ]] && listname="blacklist"

    if [[ "${list}" == "${whitelist}" || "${list}" == "${blacklist}" ]]; then
        [[ "${list}" == "${whitelist}" && -z "${type}" ]] && type="--whitelist-only"
        [[ "${list}" == "${blacklist}" && -z "${type}" ]] && type="--blacklist-only"
        bool=true
        # Is the domain in the list we want to add it to?
        grep -Ex -q "${domain}" "${list}" > /dev/null 2>&1 || bool=false

        if [[ "${bool}" == false ]]; then
            # Domain not found in the whitelist file, add it!
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} Adding ${1} to ${listname}..."
            fi
            reload=true
            # Add it to the list we want to add it to
            echo "$1" >> "${list}"
        else
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} ${1} already exists in ${listname}, no need to add!"
            fi
        fi
    elif [[ "${list}" == "${regexlist}" ]]; then
        [[ -z "${type}" ]] && type="--wildcard-only"
        bool=true
        domain="${1}"

        [[ "${wildcard}" == true ]] && domain="(^|\\.)${domain//\./\\.}$"

        # Is the domain in the list?
        # Search only for exactly matching lines
        grep -Fx "${domain}" "${regexlist}" > /dev/null 2>&1 || bool=false

        if [[ "${bool}" == false ]]; then
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} Adding ${domain} to regex list..."
            fi
            reload="restart"
            echo "$domain" >> "${regexlist}"
        else
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} ${domain} already exists in regex list, no need to add!"
            fi
        fi
    fi
}

RemoveDomain() {
    list="$2"
    domain=$(EscapeRegexp "$1")

    [[ "${list}" == "${whitelist}" ]] && listname="whitelist"
    [[ "${list}" == "${blacklist}" ]] && listname="blacklist"

    if [[ "${list}" == "${whitelist}" || "${list}" == "${blacklist}" ]]; then
        bool=true
        [[ "${list}" == "${whitelist}" && -z "${type}" ]] && type="--whitelist-only"
        [[ "${list}" == "${blacklist}" && -z "${type}" ]] && type="--blacklist-only"
        # Is it in the list? Logic follows that if its whitelisted it should not be blacklisted and vice versa
        grep -Ex -q "${domain}" "${list}" > /dev/null 2>&1 || bool=false
        if [[ "${bool}" == true ]]; then
            # Remove it from the other one
            echo -e "  ${INFO} Removing $1 from ${listname}..."
            # /I flag: search case-insensitive
            sed -i "/${domain}/Id" "${list}"
            reload=true
        else
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} ${1} does not exist in ${listname}, no need to remove!"
            fi
        fi
    elif [[ "${list}" == "${regexlist}" ]]; then
        [[ -z "${type}" ]] && type="--wildcard-only"
        domain="${1}"

        [[ "${wildcard}" == true ]] && domain="(^|\\.)${domain//\./\\.}$"

        bool=true
        # Is it in the list?
        grep -Fx "${domain}" "${regexlist}" > /dev/null 2>&1 || bool=false
        if [[ "${bool}" == true ]]; then
            # Remove it from the other one
            echo -e "  ${INFO} Removing $domain from regex list..."
            local lineNumber
            lineNumber=$(grep -Fnx "$domain" "${list}" | cut -f1 -d:)
            sed -i "${lineNumber}d" "${list}"
            reload=true
        else
            if [[ "${verbose}" == true ]]; then
                echo -e "  ${INFO} ${domain} does not exist in regex list, no need to remove!"
            fi
        fi
    fi
}

# Update Gravity
Reload() {
    echo ""
    pihole -g --skip-download "${type:-}"
}

Displaylist() {
    if [[ -f ${listMain} ]]; then
        if [[ "${listMain}" == "${whitelist}" ]]; then
            string="gravity resistant domains"
        else
            string="domains caught in the sinkhole"
        fi
        verbose=false
        echo -e "Displaying $string:\n"
        count=1
        while IFS= read -r RD || [ -n "${RD}" ]; do
            echo "  ${count}: ${RD}"
            count=$((count+1))
        done < "${listMain}"
    else
        echo -e "  ${COL_LIGHT_RED}${listMain} does not exist!${COL_NC}"
    fi
    exit 0;
}

NukeList() {
    if [[ -f "${listMain}" ]]; then
        # Back up original list
        cp "${listMain}" "${listMain}.bck~"
        # Empty out file
        echo "" > "${listMain}"
    fi
}

for var in "$@"; do
    case "${var}" in
        "-w" | "whitelist"   ) listMain="${whitelist}"; listAlt="${blacklist}";;
        "-b" | "blacklist"   ) listMain="${blacklist}"; listAlt="${whitelist}";;
        "--wild" | "wildcard" ) listMain="${regexlist}"; wildcard=true;;
        "--regex" | "regex"   ) listMain="${regexlist}";;
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

PoplistFile

if [[ "${reload}" != false ]]; then
    # Ensure that "restart" is used for Wildcard updates
    Reload "${reload}"
fi
