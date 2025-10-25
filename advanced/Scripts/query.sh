#!/usr/bin/env sh

# Pi-hole: A black hole for Internet advertisements
# (c) 2023 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Search Adlists
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Globals
PI_HOLE_INSTALL_DIR="/opt/pihole"
max_results="20"
partial="false"
domain=""

# Source color table
colfile="/opt/pihole/COL_TABLE"
# shellcheck source="./advanced/Scripts/COL_TABLE"
. "${colfile}"

# Source api functions
# shellcheck source="./advanced/Scripts/api.sh"
. "${PI_HOLE_INSTALL_DIR}/api.sh"

Help() {
    echo "Usage: pihole -q [option] <domain>
Example: 'pihole -q --partial domain.com'
Query the adlists for a specified domain

Options:
  --partial            Search the adlists for partially matching domains
  --all                Return all query matches within the adlists
  -h, --help           Show this help dialog"
    exit 0
}

GenerateOutput() {
    local counts data num_gravity num_lists search_type_str
    local gravity_data_csv lists_data_csv line url type color
    data="${1}"

    # Get count of list and gravity matches
    # Use JQ to count number of entries in lists and gravity
    # (output is number of list matches then number of gravity matches)
    counts=$(printf %s "${data}" | jq --raw-output '(.search.domains | length), (.search.gravity | group_by(.address,.type) | length)')
    num_lists=$(echo "$counts" | sed -n '1p')
    num_gravity=$(echo "$counts" | sed -n '2p')

    if [ "${partial}" = true ]; then
        search_type_str="partially"
    else
        search_type_str="exactly"
    fi

    # Results from allow/deny list
    printf "%s\n\n" "Found ${num_lists} domains ${search_type_str} matching '${COL_BLUE}${domain}${COL_NC}'."
    if [ "${num_lists}" -gt 0 ]; then
        # Convert the data to a csv, each line is a "domain,type" string
        # not using jq's @csv here as it quotes each value individually
        lists_data_csv=$(printf %s "${data}" | jq --raw-output '.search.domains | map([.domain, .type] | join(",")) | join("\n")')

        # Generate output for each csv line, separating line in a domain and type substring at the ','
        echo "${lists_data_csv}" | while read -r line; do
            printf "%s\n\n" "  - ${COL_GREEN}${line%,*}${COL_NC} (type: exact ${line#*,} domain)"
        done
    fi

    # Results from gravity
    printf "%s\n\n" "Found ${num_gravity} lists ${search_type_str} matching '${COL_BLUE}${domain}${COL_NC}'."
    if [ "${num_gravity}" -gt 0 ]; then
        # Convert the data to a csv, each line is a "URL,type,domain,domain,...." string
        # not using jq's @csv here as it quotes each value individually
        gravity_data_csv=$(printf %s "${data}" | jq --raw-output '.search.gravity | group_by(.address,.type) | map([.[0].address, .[0].type, (.[] | .domain)] | join(",")) | join("\n")')

        # Generate line-by-line output for each csv line
        echo "${gravity_data_csv}" | while read -r line; do
            # Get first part of the line, the URL
            url=${line%%,*}

            # cut off URL, leaving "type,domain,domain,...."
            line=${line#*,}
            type=${line%%,*}
            # type == "block" -> red, type == "allow" -> green
            if [ "${type}" = "block" ]; then
                color="${COL_RED}"
            else
                color="${COL_GREEN}"
            fi

            # print adlist URL
            printf "%s (%s)\n\n" "  - ${COL_BLUE}${url}${COL_NC}" "${color}${type}${COL_NC}"

            # cut off type, leaving "domain,domain,...."
            line=${line#*,}
            # Replace commas with newlines and format output
            echo "${line}" | sed 's/,/\n/g' | sed "s/^/    - ${COL_GREEN}/" | sed "s/$/${COL_NC}/"
            printf "\n\n"
        done
    fi

    # If no exact results were found, suggest using partial matching
    if [ "${num_lists}" -eq 0 ] && [ "${num_gravity}" -eq 0 ] && [ "${partial}" = false ]; then
        printf "%s\n" "Hint: Try partial matching with"
        printf "%s\n\n" "  ${COL_GREEN}pihole -q --partial ${domain}${COL_NC}"
    fi
}

Main() {
    local data

    if [ -z "${domain}" ]; then
        echo "No domain specified"
        exit 1
    fi
    # domains are lowercased and converted to punycode by FTL since
    # https://github.com/pi-hole/FTL/pull/1715
    # no need to do it here

    # Authenticate with FTL
    LoginAPI

    # send query again
    data=$(GetFTLData "search/${domain}?N=${max_results}&partial=${partial}")

    GenerateOutput "${data}"

    # Delete session
    LogoutAPI
}

# Process all options (if present)
while [ "$#" -gt 0 ]; do
    case "$1" in
    "-h" | "--help") Help ;;
    "--partial") partial="true" ;;
    "--all") max_results=10000 ;; # hard-coded FTL limit
    *) domain=$1 ;;
    esac
    shift
done

Main "${domain}"
