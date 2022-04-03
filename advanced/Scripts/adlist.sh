#!/usr/bin/env bash
# shellcheck disable=SC1090

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Remove ad lists
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Globals
piholeDir="/etc/pihole"
GRAVITYDB="${piholeDir}/gravity.db"
# Source pihole-FTL from install script
pihole_FTL="${piholeDir}/pihole-FTL.conf"
if [[ -f "${pihole_FTL}" ]]; then
    source "${pihole_FTL}"
fi

# Set this only after sourcing pihole-FTL.conf as the gravity database path may
# have changed
gravityDBfile="${GRAVITYDB}"

verbose=true

colfile="/opt/pihole/COL_TABLE"
if [[ -f "${colfile}" ]]; then
    source "${colfile}"
fi

HelpFunc() {
    local listname param

    echo "Usage: pihole -${param} [options] <domain> <domain2 ...>
Example: 'pihole -${param} site.com', or 'pihole -${param} site1.com site2.com'
${listname^} one or more domains

Options:
  -h, --help                   Show this help dialog
  -q, --quiet                  Make output less verbose
  -l, --list                   Display all your ad lists
  -d 'id', --delmode 'id'      Remove ad list from the database"

  exit 0
}

ValidateId() {
    # This function checks, whether an Id is available in the database.

    # Id is given as parameter
    id="$1"

    # Exit, if id is not an integer
    # This is important, as otherwise unsanitized user input is directly fed to the database
    if ! [[ "${id}" =~ ^[0-9]+$ ]]
    then
        if [[ "${verbose}" == "true" ]]
        then
            echo -e "Id ${id} is not valid."
        fi
        exit 1
    fi

    # Return count of id, either 0 or 1
    return "$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM adlist WHERE id = '${id}';")"
}

DisplayAdlist() {
    # This function outputs all ad lists in the database to stdout.

    # sqlite3 outputs formatted columns
    sqlite3 -header -column "${gravityDBfile}" "SELECT id, address FROM adlist ORDER BY id;"

    exit 0
}

RemoveAdlist() {
    # This function removes an adlist from the database.

    # Id is given as parameter
    id="$1"

    # getopt sets parameters into single quotes.
    # Remove single quotes
    id=$(echo "${id}" | sed -e "s/'//g")

    # Validate id before removing
    ValidateId "${id}"
    idCount=$?
    if [[ idCount -ne 1 ]]
    then
        if [[ "${verbose}" == "true" ]]
        then
            echo -e "Could not find id '${id}' in database."
        fi
        exit 1
    fi

    # Get address of id for user output
    address="$(sqlite3 "${gravityDBfile}" "SELECT address FROM adlist WHERE id='${id}';")"

    # Remove from adlist
    if [[ $(sqlite3 "${gravityDBfile}" "DELETE FROM adlist WHERE id=='${id}';") -ne 0 ]]
    then
        if [[ "${verbose}" == "true" ]]
        then
            echo -e "There was a problem removing id '${id}' from database."
            echo -e "Could not remove id from table 'adlist' in database."
        fi
        exit 1
    fi
        
    # Remove from group
    if [[ $(sqlite3 "${gravityDBfile}" "DELETE FROM adlist_by_group WHERE adlist_id==${id};") -ne 0 ]]
    then
        if [[ "${verbose}" == "true" ]]
        then
            echo -e "There was a problem removing id '${id}' from database."
            echo -e "Could not remove id from table 'adlist_by_group' in database."
        fi
        exit 1
    fi

    # Report success
    if [[ "${verbose}" == "true" ]]
    then
        echo -e "Ad list with id '${id}' and address '${address}' successfully removed from database."
    fi
    exit 0
}

# options may be followed by one colon to indicate they have a required argument
if ! options=$(getopt -o hqld: -l help,quiet,list,delete: -- "$@")
then
    # something went wrong, getopt will put out an error message for us
    echo -e ""
    HelpFunc
    exit 1
fi

set -- $options

# Options set
optionsHelpFunc="true"
optionsDisplayAdlist="false"
optionsRemoveAdlist="false"
optionsRemoveAdlistParam=""

while [ $# -gt 0 ]
do
    case $1 in
        h|--help) optionsHelpFunc=true;;
        q|--quiet) verbose=false;;
        l|--list) optionsHelpFunc=false; optionsDisplayAdlist=true;;
        # for options with required arguments, an additional shift is required
        d|--delete) optionsHelpFunc=false; optionsRemoveAdlist=true; optionsRemoveAdlistParam="${2}"; shift;;
        (--) shift; break;;
        (-*) optionsHelpFunc=true;;
        (*) break;;
    esac
    shift
done

if [[ "${optionsHelpFunc}" == "true" ]]
then
    HelpFunc
fi

if [[ "${optionsDisplayAdlist}" == "true" ]]
then
    DisplayAdlist
fi

if [[ "${optionsRemoveAdlist}" == "true" ]]
then
    RemoveAdlist "${optionsRemoveAdlistParam}"
fi

exit 0
