#!/usr/bin/env bash

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# allowlist and denylist domains
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
readonly utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck source="./advanced/Scripts/utils.sh"
source "${utilsfile}"

readonly apifile="${PI_HOLE_SCRIPT_DIR}/api.sh"
# shellcheck source="./advanced/Scripts/api.sh"
source "${apifile}"

# Determine database location
DBFILE=$(getFTLConfigValue "files.database")
if [ -z "$DBFILE" ]; then
    DBFILE="/etc/pihole/pihole-FTL.db"
fi

# Determine gravity database location
GRAVITYDB=$(getFTLConfigValue "files.gravity")
if [ -z "$GRAVITYDB" ]; then
    GRAVITYDB="/etc/pihole/gravity.db"
fi

addmode=true
verbose=true
wildcard=false

domList=()

typeId=""
comment=""

colfile="/opt/pihole/COL_TABLE"
# shellcheck source="./advanced/Scripts/COL_TABLE"
source ${colfile}

helpFunc() {
    echo "Usage: pihole ${abbrv} [options] <domain> <domain2 ...>
Example: 'pihole ${abbrv} site.com', or 'pihole ${abbrv} site1.com site2.com'
${typeId^} one or more ${kindId} domains

Options:
  remove, delete, -d  Remove domain(s)
  -q, --quiet         Make output less verbose
  -h, --help          Show this help dialog
  -l, --list          Display domains
  --comment \"text\"    Add a comment to the domain. If adding multiple domains the same comment will be used for all"

  exit 0
}

CreateDomainList() {
    # Format domain into regex filter if requested
    local dom=${1}
    if [[ "${wildcard}" == true ]]; then
        dom="(\\.|^)${dom//\./\\.}$"
    fi
    domList=("${domList[@]}" "${dom}")
}

AddDomain() {
    local json num data

    # Authenticate with the API
    LoginAPI

    # Prepare request to POST /api/domains/{type}/{kind}
    # Build JSON object of the following form
    #  {
    #    "domain": [ <domains> ],
    #    "comment": <comment>
    #  }
    # where <domains> is an array of domain strings and <comment> is a string
    # We use jq to build the JSON object
    json=$(jq --null-input --compact-output --arg domains "${domList[*]}" --arg comment "${comment}" '{domain: $domains | split(" "), comment: $comment}')

    # Send the request
    data=$(PostFTLData "domains/${typeId}/${kindId}" "${json}")

    # Display domain(s) added
    # (they are listed in .processed.success, use jq)
    num=$(echo "${data}" | jq '.processed.success | length')
    if [[ "${num}" -gt 0 ]] && [[ "${verbose}" == true ]]; then
        echo -e "  ${TICK} Added ${num} domain(s):"
        for i in $(seq 0 $((num-1))); do
            echo -e "    - ${COL_BLUE}$(echo "${data}" | jq --raw-output ".processed.success[$i].item")${COL_NC}"
        done
    fi
    # Display failed domain(s)
    # (they are listed in .processed.errors, use jq)
    num=$(echo "${data}" | jq '.processed.errors | length')
    if [[ "${num}" -gt 0 ]] && [[ "${verbose}" == true ]]; then
        echo -e "  ${CROSS} Failed to add ${num} domain(s):"
        for i in $(seq 0 $((num-1))); do
            echo -e "    - ${COL_BLUE}$(echo "${data}" | jq --raw-output ".processed.errors[$i].item")${COL_NC}"
            error=$(echo "${data}" | jq --raw-output ".processed.errors[$i].error")
            if [[ "${error}" == "UNIQUE constraint failed: domainlist.domain, domainlist.type" ]]; then
                error="Domain already in the specified list"
            fi
            echo -e "      ${error}"
        done
    fi

    # Log out
    LogoutAPI
}

RemoveDomain() {
    local json num data status

    # Authenticate with the API
    LoginAPI

    # Prepare request to POST /api/domains:batchDelete
    # Build JSON object of the following form
    #  [{
    #    "item": <domain>,
    #    "type": "${typeId}",
    #    "kind": "${kindId}",
    #  }]
    # where <domain> is the domain string and ${typeId} and ${kindId} are the type and kind IDs
    # We use jq to build the JSON object)
    json=$(jq --null-input --compact-output --arg domains "${domList[*]}" --arg typeId "${typeId}" --arg kindId "${kindId}" '[ $domains | split(" ")[] as $item | {item: $item, type: $typeId, kind: $kindId} ]')

    # Send the request
    data=$(PostFTLData "domains:batchDelete" "${json}" "status")
    # Separate the status from the data
    status=$(printf %s "${data#"${data%???}"}")
    data=$(printf %s "${data%???}")

    # If there is an .error object in the returned data, display it
    local error
    error=$(jq --compact-output <<< "${data}" '.error')
    if [[ $error != "null" && $error != "" ]]; then
        echo -e "  ${CROSS} Failed to remove domain(s):"
        echo -e "      $(jq <<< "${data}" '.error')"
    elif [[ "${verbose}" == true && "${status}" == "204" ]]; then
        echo -e "  ${TICK} Domain(s) removed from the ${kindId} ${typeId}list"
    elif [[ "${verbose}" == true && "${status}" == "404" ]]; then
        echo -e "  ${TICK} Requested domain(s) not found on ${kindId} ${typeId}list"
    fi

    # Log out
    LogoutAPI
}

Displaylist() {
    local data

    # if either typeId or kindId is empty, we cannot display the list
    if [[ -z "${typeId}" ]] || [[ -z "${kindId}" ]]; then
        echo "  ${CROSS} Unable to display list. Please specify a list type and kind."
        exit 1
    fi

    # Authenticate with the API
    LoginAPI

    # Send the request
    data=$(GetFTLData "domains/${typeId}/${kindId}")

    # Display the list
    num=$(echo "${data}" | jq '.domains | length')
    if [[ "${num}" -gt 0 ]]; then
        echo -e "  ${TICK} Found ${num} domain(s) in the ${kindId} ${typeId}list:"
        for i in $(seq 0 $((num-1))); do
            echo -e "    - ${COL_BLUE}$(echo "${data}" | jq --compact-output ".domains[$i].domain")${COL_NC}"
            echo -e "      Comment: $(echo "${data}" | jq --compact-output ".domains[$i].comment")"
            echo -e "      Groups: $(echo "${data}" | jq --compact-output ".domains[$i].groups")"
            echo -e "      Added: $(date -d @"$(echo "${data}" | jq --compact-output ".domains[$i].date_added")")"
            echo -e "      Last modified: $(date -d @"$(echo "${data}" | jq --compact-output ".domains[$i].date_modified")")"
        done
    else
        echo -e "  ${INFO} No domains found in the ${kindId} ${typeId}list"
    fi

    # Log out
    LogoutAPI

    # Return early without adding/deleting domains
    exit 0
}

GetComment() {
    comment="$1"
    if [[ "${comment}" =~ [^a-zA-Z0-9_\#:/\.,\ -] ]]; then
        echo "  ${CROSS} Found invalid characters in domain comment!"
        exit 1
    fi
}

while (( "$#" )); do
    case "${1}" in
        "allow" | "allowlist" ) kindId="exact"; typeId="allow"; abbrv="allow";;
        "deny" | "denylist"   ) kindId="exact"; typeId="deny"; abbrv="deny";;
        "--allow-regex" | "allow-regex" ) kindId="regex"; typeId="allow"; abbrv="--allow-regex";;
        "--allow-wild" | "allow-wild" ) kindId="regex"; typeId="allow"; wildcard=true; abbrv="--allow-wild";;
        "--regex" | "regex"   ) kindId="regex"; typeId="deny"; abbrv="--regex";;
        "--wild" | "wildcard" ) kindId="regex"; typeId="deny"; wildcard=true; abbrv="--wild";;
        "-d" | "remove" | "delete" ) addmode=false;;
        "-q" | "--quiet"     ) verbose=false;;
        "-h" | "--help"      ) helpFunc;;
        "-l" | "--list"      ) Displaylist;;
        "--comment"          ) GetComment "${2}"; shift;;
        *                    ) CreateDomainList "${1}";;
    esac
    shift
done

shift

if [[ ${#domList[@]} == 0 ]]; then
    helpFunc
fi

if ${addmode}; then
    AddDomain
else
    RemoveDomain
fi
