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
GRAVITYDB="${piholeDir}/gravity.db"
options="$*"
all=""
exact=""
matchType="match"
# Source pihole-FTL from install script
pihole_FTL="${piholeDir}/pihole-FTL.conf"
if [[ -f "${pihole_FTL}" ]]; then
    source "${pihole_FTL}"
fi

# Set this only after sourcing pihole-FTL.conf as the gravity database path may
# have changed
gravityDBfile="${GRAVITYDB}"

colfile="/opt/pihole/COL_TABLE"
source "${colfile}"

if [[ "${options}" == "-h" ]] || [[ "${options}" == "--help" ]]; then
    echo "Usage: pihole -q [option] <domain>
Example: 'pihole -q -exact domain.com'
Query the adlists for a specified domain

Options:
  -exact              Search the adlists for exact domain matches
  -all                Return all query matches within the adlists
  -h, --help          Show this help dialog"
  exit 0
fi

# Handle valid options
[[ "${options}" == *"-all"* ]] && all=true
if [[ "${options}" == *"-exact"* ]]; then
    exact="exact"; matchType="exact ${matchType}"
fi

# Strip valid options, leaving only the domain and invalid options
# This allows users to place the options before or after the domain
options=$(sed -E 's/ ?-(all|exact) ?//g' <<< "${options}")

# Handle remaining options
# If $options contain non ASCII characters, convert to punycode
case "${options}" in
    ""             ) str="No domain specified";;
    *" "*          ) str="Unknown query option specified";;
    *[![:ascii:]]* ) rawDomainQuery=$(idn2 "${options}");;
    *              ) rawDomainQuery="${options}";;
esac

# convert the domain to lowercase
domainQuery=$(echo "${rawDomainQuery}" | tr '[:upper:]' '[:lower:]')

if [[ -n "${str:-}" ]]; then
    echo -e "${str}${COL_NC}\\nTry 'pihole -q --help' for more information."
    exit 1
fi

# Scan a domain again a list of RegEX
scanRegExList(){
    local domain="${1}" list="${2}"

    for entry in ${list}; do
        if [[ "${domain}" =~ ${entry} ]]; then
            printf "%b\n" "${entry}";
        fi
    done

}

scanDatabaseTable() {
    local domain table list_type querystr result extra abpquerystr abpfound abpentry searchstr
    domain="$(printf "%q" "${1}")"
    table="${2}"
    list_type="${3:-}"

    # As underscores are legitimate parts of domains, we escape them when using the LIKE operator.
    # Underscores are SQLite wildcards matching exactly one character. We obviously want to suppress this
    # behavior. The "ESCAPE '\'" clause specifies that an underscore preceded by an '\' should be matched
    # as a literal underscore character. We pretreat the $domain variable accordingly to escape underscores.
    if [[ "${table}" == "gravity" ]]; then

        # Are there ABP entries on gravity?
        # Return 1 if abp_domain=1 or Zero if abp_domain=0 or not set
        abpquerystr="SELECT EXISTS (SELECT 1 FROM info WHERE property='abp_domains' and value='1')"
        abpfound="$(pihole-FTL sqlite3 "${gravityDBfile}" "${abpquerystr}")" 2> /dev/null

        # Create search string for ABP entries only if needed
        if [ "${abpfound}" -eq 1 ]; then
            abpentry="${domain}"

            searchstr="'||${abpentry}^'"

            # While a dot is found ...
            while [ "${abpentry}" != "${abpentry/./}" ]
            do
                # ... remove text before the dot (including the dot) and append the result to $searchstr
                abpentry=$(echo "${abpentry}" | cut -f 2- -d '.')
                searchstr="$searchstr, '||${abpentry}^'"
            done

            # The final search string will look like:
            # "domain IN ('||sub2.sub1.domain.com^', '||sub1.domain.com^', '||domain.com^', '||com^') OR"
            searchstr="domain IN (${searchstr}) OR "
        fi

        case "${exact}" in
            "exact" ) querystr="SELECT gravity.domain,adlist.address,adlist.enabled FROM gravity LEFT JOIN adlist ON adlist.id = gravity.adlist_id WHERE domain = '${domain}'";;
            *       ) querystr="SELECT gravity.domain,adlist.address,adlist.enabled FROM gravity LEFT JOIN adlist ON adlist.id = gravity.adlist_id WHERE ${searchstr} domain LIKE '%${domain//_/\\_}%' ESCAPE '\\'";;
        esac
    else
        case "${exact}" in
            "exact" ) querystr="SELECT domain,enabled FROM domainlist WHERE type = '${list_type}' AND domain = '${domain}'";;
            *       ) querystr="SELECT domain,enabled FROM domainlist WHERE type = '${list_type}' AND domain LIKE '%${domain//_/\\_}%' ESCAPE '\\'";;
        esac
    fi

    # Send prepared query to gravity database
    result="$(pihole-FTL sqlite3 -separator ',' "${gravityDBfile}" "${querystr}")" 2> /dev/null
    if [[ -z "${result}" ]]; then
        # Return early when there are no matches in this table
        return
    fi

    if [[ "${table}" == "gravity" ]]; then
        echo "${result}"
        return
    fi

    # Mark domain as having been white-/blacklist matched (global variable)
    wbMatch=true

    # Print table name
    echo " ${matchType^} found in ${COL_BOLD}exact ${table}${COL_NC}"

    # Loop over results and print them
    mapfile -t results <<< "${result}"
    for result in "${results[@]}"; do
        domain="${result/,*}"
        if [[ "${result#*,}" == "0" ]]; then
            extra=" (disabled)"
        else
            extra=""
        fi
        echo "   ${domain}${extra}"
    done
}

scanRegexDatabaseTable() {
    local domain list list_type
    domain="${1}"
    list="${2}"
    list_type="${3:-}"

    # Query all regex from the corresponding database tables
    mapfile -t regexList < <(pihole-FTL sqlite3 "${gravityDBfile}" "SELECT domain FROM domainlist WHERE type = ${list_type}" 2> /dev/null)

    # If we have regexps to process
    if [[ "${#regexList[@]}" -ne 0 ]]; then
        # Split regexps over a new line
        str_regexList=$(printf '%s\n' "${regexList[@]}")
        # Check domain against regexps
        mapfile -t regexMatches < <(scanRegExList "${domain}" "${str_regexList}")
        # If there were regex matches
        if [[  "${#regexMatches[@]}" -ne 0 ]]; then
            # Split matching regexps over a new line
            str_regexMatches=$(printf '%s\n' "${regexMatches[@]}")
            # Form a "matched" message
            str_message="${matchType^} found in ${COL_BOLD}regex ${list}${COL_NC}"
            # Form a "results" message
            str_result="${COL_BOLD}${str_regexMatches}${COL_NC}"
            # If we are displaying more than just the source of the block
            # Set the wildcard match flag
            wcMatch=true
            # Echo the "matched" message, indented by one space
            echo " ${str_message}"
            # Echo the "results" message, each line indented by three spaces
            # shellcheck disable=SC2001
            echo "${str_result}" | sed 's/^/   /'
        fi
    fi
}

# Scan Whitelist and Blacklist
scanDatabaseTable "${domainQuery}" "whitelist" "0"
scanDatabaseTable "${domainQuery}" "blacklist" "1"

# Scan Regex table
scanRegexDatabaseTable "${domainQuery}" "whitelist" "2"
scanRegexDatabaseTable "${domainQuery}" "blacklist" "3"

# Query block lists
mapfile -t results <<< "$(scanDatabaseTable "${domainQuery}" "gravity")"

# Handle notices
if [[ -z "${wbMatch:-}" ]] && [[ -z "${wcMatch:-}" ]] && [[ -z "${results[*]}" ]]; then
    echo -e "  ${INFO} No ${exact/t/t }results found for ${COL_BOLD}${domainQuery}${COL_NC} within the adlists"
    exit 0
elif [[ -z "${results[*]}" ]]; then
    # Result found in WL/BL/Wildcards
    exit 0
elif [[ -z "${all}" ]] && [[ "${#results[*]}" -ge 100 ]]; then
    echo -e "  ${INFO} Over 100 ${exact/t/t }results found for ${COL_BOLD}${domainQuery}${COL_NC}
        This can be overridden using the -all option"
    exit 0
fi

# Print "Exact matches for" title
if [[ -n "${exact}" ]]; then
    plural=""; [[ "${#results[*]}" -gt 1 ]] && plural="es"
    echo " ${matchType^}${plural} for ${COL_BOLD}${domainQuery}${COL_NC} found in:"
fi

for result in "${results[@]}"; do
    match="${result/,*/}"
    extra="${result#*,}"
    adlistAddress="${extra/,*/}"
    extra="${extra#*,}"
    if [[ "${extra}" == "0" ]]; then
        extra=" (disabled)"
    else
        extra=""
    fi

    if [[ -n "${exact}" ]]; then
        echo "  - ${adlistAddress}${extra}"
    else
        if [[ ! "${adlistAddress}" == "${adlistAddress_prev:-}" ]]; then
            count=""
            echo " ${matchType^} found in ${COL_BOLD}${adlistAddress}${COL_NC}:"
            adlistAddress_prev="${adlistAddress}"
        fi
        : $((count++))

        # Print matching domain if $max_count has not been reached
        [[ -z "${all}" ]] && max_count="50"
        if [[ -z "${all}" ]] && [[ "${count}" -ge "${max_count}" ]]; then
            [[ "${count}" -gt "${max_count}" ]] && continue
            echo "   ${COL_GRAY}Over ${count} results found, skipping rest of file${COL_NC}"
        else
            echo "   ${match}${extra}"
        fi
    fi
done

exit 0
