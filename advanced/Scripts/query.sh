#!/usr/bin/env bash
# shellcheck disable=SC1090
# Pi-hole: A black hole for Internet advertisements
# (c) 2018 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Query Domain Lists
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Globals
piholeDir="/etc/pihole"
adListsList="$piholeDir/adlists.list"
wildcardlist="/etc/dnsmasq.d/03-pihole-wildcard.conf"
options="$*"
adlist=""
all=""
exact=""
blockpage=""
matchType="match"

colfile="/opt/pihole/COL_TABLE"
source "${colfile}"

# Print each subdomain
# e.g: foo.bar.baz.com = "foo.bar.baz.com bar.baz.com baz.com com"
processWildcards() {
    IFS="." read -r -a array <<< "${1}"
    for (( i=${#array[@]}-1; i>=0; i-- )); do
        ar=""
        for (( j=${#array[@]}-1; j>${#array[@]}-i-2; j-- )); do
            if [[ $j == $((${#array[@]}-1)) ]]; then
                ar="${array[$j]}"
            else
                ar="${array[$j]}.${ar}"
            fi
        done
        echo "${ar}"
    done
}

# Scan an array of files for matching strings
scanList(){
    # Escape full stops
    local domain="${1//./\\.}" lists="${2}" type="${3:-}"

    # Prevent grep from printing file path
    cd "$piholeDir" || exit 1

    # Prevent grep -i matching slowly: http://bit.ly/2xFXtUX
    export LC_CTYPE=C

    # /dev/null forces filename to be printed when only one list has been generated
    # shellcheck disable=SC2086
    case "${type}" in
        "exact" ) grep -i -E "(^|\\s)${domain}($|\\s|#)" ${lists} /dev/null 2>/dev/null;;
        "wc"    ) grep -i -o -m 1 "/${domain}/" ${lists} 2>/dev/null;;
        *       ) grep -i "${domain}" ${lists} /dev/null 2>/dev/null;;
    esac
}

if [[ "${options}" == "-h" ]] || [[ "${options}" == "--help" ]]; then
    echo "Usage: pihole -q [option] <domain>
Example: 'pihole -q -exact domain.com'
Query the adlists for a specified domain

Options:
  -adlist             Print the name of the block list URL
  -exact              Search the block lists for exact domain matches
  -all                Return all query matches within a block list
  -h, --help          Show this help dialog"
  exit 0
fi

if [[ ! -e "$adListsList" ]]; then
    echo -e "${COL_LIGHT_RED}The file $adListsList was not found${COL_NC}"
    exit 1
fi

# Handle valid options
if [[ "${options}" == *"-bp"* ]]; then
    exact="exact"; blockpage=true
else
    [[ "${options}" == *"-adlist"* ]] && adlist=true
    [[ "${options}" == *"-all"* ]] && all=true
    if [[ "${options}" == *"-exact"* ]]; then
        exact="exact"; matchType="exact ${matchType}"
    fi
fi

# Strip valid options, leaving only the domain and invalid options
# This allows users to place the options before or after the domain
options=$(sed -E 's/ ?-(bp|adlists?|all|exact) ?//g' <<< "${options}")

# Handle remaining options
# If $options contain non ASCII characters, convert to punycode
case "${options}" in
    ""             ) str="No domain specified";;
    *" "*          ) str="Unknown query option specified";;
    *[![:ascii:]]* ) domainQuery=$(idn2 "${options}");;
    *              ) domainQuery="${options}";;
esac

if [[ -n "${str:-}" ]]; then
    echo -e "${str}${COL_NC}\\nTry 'pihole -q --help' for more information."
    exit 1
fi

# Scan Whitelist and Blacklist
lists="whitelist.txt blacklist.txt"
mapfile -t results <<< "$(scanList "${domainQuery}" "${lists}" "${exact}")"
if [[ -n "${results[*]}" ]]; then
    wbMatch=true
    # Loop through each result in order to print unique file title once
    for result in "${results[@]}"; do
        fileName="${result%%.*}"
        if [[ -n "${blockpage}" ]]; then
            echo "π ${result}"
            exit 0
        elif [[ -n "${exact}" ]]; then
            echo " ${matchType^} found in ${COL_BOLD}${fileName^}${COL_NC}"
        else
            # Only print filename title once per file
            if [[ ! "${fileName}" == "${fileName_prev:-}" ]]; then
                echo " ${matchType^} found in ${COL_BOLD}${fileName^}${COL_NC}"
                fileName_prev="${fileName}"
            fi
        echo "   ${result#*:}"
        fi
    done
fi

# Scan Wildcards
if [[ -e "${wildcardlist}" ]]; then
    # Determine all subdomains, domain and TLDs
    mapfile -t wildcards <<< "$(processWildcards "${domainQuery}")"
    for match in "${wildcards[@]}"; do
        # Search wildcard list for matches
        mapfile -t results <<< "$(scanList "${match}" "${wildcardlist}" "wc")"
        if [[ -n "${results[*]}" ]]; then
            if [[ -z "${wcMatch:-}" ]] && [[ -z "${blockpage}" ]]; then
                wcMatch=true
                echo " ${matchType^} found in ${COL_BOLD}Wildcards${COL_NC}:"
            fi
            case "${blockpage}" in
                true ) echo "π ${wildcardlist##*/}"; exit 0;;
                *    ) echo "   *.${match}";;
            esac
        fi
    done
fi

# Get version sorted *.domains filenames (without dir path)
lists=("$(cd "$piholeDir" || exit 0; printf "%s\\n" -- *.domains | sort -V)")

# Query blocklists for occurences of domain
mapfile -t results <<< "$(scanList "${domainQuery}" "${lists[*]}" "${exact}")"

# Remove unwanted content from $results
# Each line in $results is formatted as such: [fileName]:[line]
# 1. Delete lines starting with #
# 2. Remove comments after domain
# 3. Remove hosts format IP address
# 4. Remove any lines that no longer contain the queried domain name (in case the matched domain name was in a comment)
esc_domain="${domainQuery//./\\.}"
mapfile -t results <<< "$(IFS=$'\n'; sed \
	-e "/:#/d" \
	-e "s/[ \\t]#.*//g" \
	-e "s/:.*[ \\t]/:/g" \
	-e "/${esc_domain}/!d" \
	<<< "${results[*]}")"

# Handle notices
if [[ -z "${wbMatch:-}" ]] && [[ -z "${wcMatch:-}" ]] && [[ -z "${results[*]}" ]]; then
    echo -e "  ${INFO} No ${exact/t/t }results found for ${COL_BOLD}${domainQuery}${COL_NC} within the block lists"
    exit 0
elif [[ -z "${results[*]}" ]]; then
    # Result found in WL/BL/Wildcards
    exit 0
elif [[ -z "${all}" ]] && [[ "${#results[*]}" -ge 100 ]]; then
    echo -e "  ${INFO} Over 100 ${exact/t/t }results found for ${COL_BOLD}${domainQuery}${COL_NC}
        This can be overridden using the -all option"
    exit 0
fi

# Get adlist file content as array
if [[ -n "${adlist}" ]] || [[ -n "${blockpage}" ]]; then
    for adlistUrl in $(< "${adListsList}"); do
        if [[ "${adlistUrl:0:4}" =~ (http|www.) ]]; then
            adlists+=("${adlistUrl}")
        fi
    done
fi

# Print "Exact matches for" title
if [[ -n "${exact}" ]] && [[ -z "${blockpage}" ]]; then
    plural=""; [[ "${#results[*]}" -gt 1 ]] && plural="es"
    echo " ${matchType^}${plural} for ${COL_BOLD}${domainQuery}${COL_NC} found in:"
fi

for result in "${results[@]}"; do
    fileName="${result/:*/}"

    # Determine *.domains URL using filename's number
    if [[ -n "${adlist}" ]] || [[ -n "${blockpage}" ]]; then
        fileNum="${fileName/list./}"; fileNum="${fileNum%%.*}"
        fileName="${adlists[$fileNum]}"

        # Discrepency occurs when adlists has been modified, but Gravity has not been run
        if [[ -z "${fileName}" ]]; then
            fileName="${COL_LIGHT_RED}(no associated adlists URL found)${COL_NC}"
        fi
    fi

    if [[ -n "${blockpage}" ]]; then
        echo "${fileNum} ${fileName}"
    elif [[ -n "${exact}" ]]; then
        echo "   ${fileName}"
    else
        if [[ ! "${fileName}" == "${fileName_prev:-}" ]]; then
            count=""
            echo " ${matchType^} found in ${COL_BOLD}${fileName}${COL_NC}:"
            fileName_prev="${fileName}"
        fi
        : $((count++))

        # Print matching domain if $max_count has not been reached
        [[ -z "${all}" ]] && max_count="50"
        if [[ -z "${all}" ]] && [[ "${count}" -ge "${max_count}" ]]; then
            [[ "${count}" -gt "${max_count}" ]] && continue
            echo "   ${COL_GRAY}Over ${count} results found, skipping rest of file${COL_NC}"
        else
            echo "   ${result#*:}"
        fi
    fi
done

exit 0
