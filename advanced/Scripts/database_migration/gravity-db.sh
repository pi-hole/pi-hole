#!/usr/bin/env bash


# Pi-hole: A black hole for Internet advertisements
# (c) 2019 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Updates gravity.db database
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly scriptPath="/etc/.pihole/advanced/Scripts/database_migration/gravity"

upgrade_gravityDB(){
    local database version
    database="${1}"

    # Exit early if the database does not exist (e.g. in CI tests)
    if [[ ! -f "${database}" ]]; then
        return
    fi

    # Get database version
    version="$(pihole-FTL sqlite3 -ni "${database}" "SELECT \"value\" FROM \"info\" WHERE \"property\" = 'version';")"

    if [[ "$version" == "1" ]]; then
        # This migration script upgraded the gravity.db file by
        # adding the domain_audit table. It is now a no-op
        echo -e "  ${INFO} Upgrading gravity database from version 1 to 2"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/1_to_2.sql"
        version=2
    fi
    if [[ "$version" == "2" ]]; then
        # This migration script upgrades the gravity.db file by
        # renaming the regex table to regex_blacklist, and
        # creating a new regex_whitelist table + corresponding linking table and views
        echo -e "  ${INFO} Upgrading gravity database from version 2 to 3"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/2_to_3.sql"
        version=3
    fi
    if [[ "$version" == "3" ]]; then
        # This migration script unifies the formally separated domain
        # lists into a single table with a UNIQUE domain constraint
        echo -e "  ${INFO} Upgrading gravity database from version 3 to 4"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/3_to_4.sql"
        version=4
    fi
    if [[ "$version" == "4" ]]; then
        # This migration script upgrades the gravity and list views
        # implementing necessary changes for per-client blocking
        echo -e "  ${INFO} Upgrading gravity database from version 4 to 5"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/4_to_5.sql"
        version=5
    fi
    if [[ "$version" == "5" ]]; then
        # This migration script upgrades the adlist view
        # to return an ID used in gravity.sh
        echo -e "  ${INFO} Upgrading gravity database from version 5 to 6"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/5_to_6.sql"
        version=6
    fi
    if [[ "$version" == "6" ]]; then
        # This migration script adds a special group with ID 0
        # which is automatically associated to all clients not
        # having their own group assignments
        echo -e "  ${INFO} Upgrading gravity database from version 6 to 7"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/6_to_7.sql"
        version=7
    fi
    if [[ "$version" == "7" ]]; then
        # This migration script recreated the group table
        # to ensure uniqueness on the group name
        # We also add date_added and date_modified columns
        echo -e "  ${INFO} Upgrading gravity database from version 7 to 8"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/7_to_8.sql"
        version=8
    fi
    if [[ "$version" == "8" ]]; then
        # This migration fixes some issues that were introduced
        # in the previous migration script.
        echo -e "  ${INFO} Upgrading gravity database from version 8 to 9"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/8_to_9.sql"
        version=9
    fi
    if [[ "$version" == "9" ]]; then
        # This migration drops unused tables and creates triggers to remove
        # obsolete groups assignments when the linked items are deleted
        echo -e "  ${INFO} Upgrading gravity database from version 9 to 10"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/9_to_10.sql"
        version=10
    fi
    if [[ "$version" == "10" ]]; then
        # This adds timestamp and an optional comment field to the client table
        # These fields are only temporary and will be replaces by the columns
        # defined in gravity.db.sql during gravity swapping. We add them here
        # to keep the copying process generic (needs the same columns in both the
        # source and the destination databases).
        echo -e "  ${INFO} Upgrading gravity database from version 10 to 11"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/10_to_11.sql"
        version=11
    fi
    if [[ "$version" == "11" ]]; then
        # Rename group 0 from "Unassociated" to "Default"
        echo -e "  ${INFO} Upgrading gravity database from version 11 to 12"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/11_to_12.sql"
        version=12
    fi
    if [[ "$version" == "12" ]]; then
        # Add column date_updated to adlist table
        echo -e "  ${INFO} Upgrading gravity database from version 12 to 13"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/12_to_13.sql"
        version=13
    fi
    if [[ "$version" == "13" ]]; then
        # Add columns number and status to adlist table
        echo -e "  ${INFO} Upgrading gravity database from version 13 to 14"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/13_to_14.sql"
        version=14
    fi
    if [[ "$version" == "14" ]]; then
        # Changes the vw_adlist created in 5_to_6
        echo -e "  ${INFO} Upgrading gravity database from version 14 to 15"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/14_to_15.sql"
        version=15
    fi
    if [[ "$version" == "15" ]]; then
        # Add column abp_entries to adlist table
        echo -e "  ${INFO} Upgrading gravity database from version 15 to 16"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/15_to_16.sql"
        version=16
    fi
    if [[ "$version" == "16" ]]; then
        # Add antigravity table
        # Add column type to adlist table (to support adlist types)
        echo -e "  ${INFO} Upgrading gravity database from version 16 to 17"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/16_to_17.sql"
        version=17
    fi
    if [[ "$version" == "17" ]]; then
        # Add adlist.id to vw_gravity and vw_antigravity
        echo -e "  ${INFO} Upgrading gravity database from version 17 to 18"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/17_to_18.sql"
        version=18
    fi
    if [[ "$version" == "18" ]]; then
        # Modify DELETE triggers to delete BEFORE instead of AFTER to prevent
        # foreign key constraint violations
        echo -e "  ${INFO} Upgrading gravity database from version 18 to 19"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/18_to_19.sql"
        version=19
    fi
    if [[ "$version" == "19" ]]; then
        # Update views to use new allowlist/denylist names
        echo -e "  ${INFO} Upgrading gravity database from version 19 to 20"
        pihole-FTL sqlite3 -ni "${database}" < "${scriptPath}/19_to_20.sql"
        version=20
    fi
}
