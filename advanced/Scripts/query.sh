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
gravityDBfile="${piholeDir}/gravity.db"
options="$*"
adlist=""
all=""
exact=""
blockpage=""
matchType="match"

colfile="/opt/pihole/COL_TABLE"
source "${colfile}"

# Scan an array of files for matching strings
scanList(){
    # Escape full stops
    local domain="${1}" esc_domain="${1//./\\.}" lists="${2}" type="${3:-}"

    # Prevent grep from printing file path
    cd "$piholeDir" || exit 1

    # Prevent grep -i matching slowly: http://bit.ly/2xFXtUX
    export LC_CTYPE=C

    # /dev/null forces filename to be printed when only one list has been generated
    # shellcheck disable=SC2086
    case "${type}" in
		"exact" ) grep -i -E -l "(^|(?<!#)\\s)${esc_domain}($|\\s|#)" ${lists} /dev/null 2>/dev/null;;
		# Create array of regexps
		# Iterate through each regexp and check whether it matches the domainQuery
		# If it does, print the matching regexp and continue looping
		# Input 1 - regexps | Input 2 - domainQuery
		"regex" ) awk 'NR==FNR{regexps[$0]}{for (r in regexps)if($0 ~ r)print r}' \
					<(echo "${lists}") <(echo "${domain}") 2>/dev/null;;
		*       ) grep -i "${esc_domain}" ${lists} /dev/null 2>/dev/null;;
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

scanDatabaseTable() {
    local domain table type querystr result
    domain="$(printf "%q" "${1}")"
    table="${2}"
    type="${3:-}"

    # As underscores are legitimate parts of domains, we escape them when using the LIKE operator.
    # Underscores are SQLite wildcards matching exactly one character. We obviously want to suppress this
    # behavior. The "ESCAPE '\'" clause specifies that an underscore preceded by an '\' should be matched
    # as a literal underscore character. We pretreat the $domain variable accordingly to escape underscores.
    case "${type}" in
		"exact" ) querystr="SELECT domain FROM vw_${table} WHERE domain = '${domain}'";;
		*       ) querystr="SELECT domain FROM vw_${table} WHERE domain LIKE '%${domain//_/\\_}%' ESCAPE '\\'";;
    esac

    # Send prepared query to gravity database
    result="$(sqlite3 "${gravityDBfile}" "${querystr}")" 2> /dev/null
    if [[ -z "${result}" ]]; then
        # Return early when there are no matches in this table
        return
    fi

    # Mark domain as having been white-/blacklist matched (global variable)
    wbMatch=true

    # Print table name
    echo " ${matchType^} found in ${COL_BOLD}${table^}${COL_NC}"

    # Loop over results and print them
    mapfile -t results <<< "${result}"
    for result in "${results[@]}"; do
        if [[ -n "${blockpage}" ]]; then
            echo "π ${result}"
            exit 0
        fi
        echo "   ${result}"
    done
}

# Scan Whitelist and Blacklist
scanDatabaseTable "${domainQuery}" "whitelist" "${exact}"
scanDatabaseTable "${domainQuery}" "blacklist" "${exact}"

# Scan Regex table
mapfile -t regexlist < <(sqlite3 "${gravityDBfile}" "SELECT domain FROM vw_regex" 2> /dev/null)

# If we have regexps to process
if [[ "${#regexlist[@]}" -ne 0 ]]; then
	# Split regexps over a new line
	str_regexlist=$(printf '%s\n' "${regexlist[@]}")
	# Check domainQuery against regexps
	mapfile -t regexMatches < <(scanList "${domainQuery}" "${str_regexlist}" "regex")
	# If there were regex matches
	if [[  "${#regexMatches[@]}" -ne 0 ]]; then
		# Split matching regexps over a new line
		str_regexMatches=$(printf '%s\n' "${regexMatches[@]}")
		# Form a "matched" message
		str_message="${matchType^} found in ${COL_BOLD}Regex list${COL_NC}"
		# Form a "results" message
		str_result="${COL_BOLD}${str_regexMatches}${COL_NC}"
		
		if [[ -z "${blockpage}" ]]; then
			# Set the wildcard match flag
			wcMatch=true
			# Echo the "matched" message, indented by one space
			echo " ${str_message}"
			# Echo the "results" message, each line indented by three spaces
			# shellcheck disable=SC2001
			echo "${str_result}" | sed 's/^/   /'
		else
			echo "π Regex list"
			exit 0
		fi
		
	fi
fi

# Get version sorted *.domains filenames (without dir path)
lists=("$(cd "$piholeDir" || exit 0; printf "%s\\n" -- *.domains | sort -V)")

# Query blocklists for occurences of domain
mapfile -t results <<< "$(scanList "${domainQuery}" "${lists[*]}" "${exact}")"

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

# Remove unwanted content from non-exact $results
if [[ -z "${exact}" ]]; then
    # Delete lines starting with #
    # Remove comments after domain
    # Remove hosts format IP address
    mapfile -t results <<< "$(IFS=$'\n'; sed \
        -e "/:#/d" \
        -e "s/[ \\t]#.*//g" \
        -e "s/:.*[ \\t]/:/g" \
        <<< "${results[*]}")"
    # Exit if result was in a comment
    [[ -z "${results[*]}" ]] && exit 0
fi

# Get adlist file content as array
if [[ -n "${adlist}" ]] || [[ -n "${blockpage}" ]]; then
    # Retrieve source URLs from gravity database
    mapfile -t adlists <<< "$(sqlite3 "${gravityDBfile}" "SELECT address FROM vw_adlists;" 2> /dev/null)"
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
