#!/usr/bin/env bash
# shellcheck disable=SC1090

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
	local database piholeDir auditFile version
	database="${1}"
	piholeDir="${2}"
	auditFile="${piholeDir}/auditlog.list"

	# Get database version
	version="$(sqlite3 "${database}" "SELECT \"value\" FROM \"info\" WHERE \"property\" = 'version';")"

	if [[ "$version" == "1" ]]; then
		# This migration script upgrades the gravity.db file by
		# adding the domain_audit table
		echo -e "  ${INFO} Upgrading gravity database from version 1 to 2"
		sqlite3 "${database}" < "${scriptPath}/1_to_2.sql"
		version=2

		# Store audit domains in database table
		if [ -e "${auditFile}" ]; then
			echo -e "  ${INFO} Migrating content of ${auditFile} into new database"
			# database_table_from_file is defined in gravity.sh
			database_table_from_file "domain_audit" "${auditFile}"
		fi
	fi
	if [[ "$version" == "2" ]]; then
		# This migration script upgrades the gravity.db file by
		# renaming the regex table to regex_blacklist, and
		# creating a new regex_whitelist table + corresponding linking table and views
		echo -e "  ${INFO} Upgrading gravity database from version 2 to 3"
		sqlite3 "${database}" < "${scriptPath}/2_to_3.sql"
		version=3
	fi
	if [[ "$version" == "3" ]]; then
		# This migration script unifies the formally separated domain
		# lists into a single table with a UNIQUE domain constraint
		echo -e "  ${INFO} Upgrading gravity database from version 3 to 4"
		sqlite3 "${database}" < "${scriptPath}/3_to_4.sql"
		version=4
	fi
	if [[ "$version" == "4" ]]; then
		# This migration script upgrades the gravity and list views
		# implementing necessary changes for per-client blocking
		echo -e "  ${INFO} Upgrading gravity database from version 4 to 5"
		sqlite3 "${database}" < "${scriptPath}/4_to_5.sql"
		version=5
	fi
	if [[ "$version" == "5" ]]; then
		# This migration script upgrades the adlist view
		# to return an ID used in gravity.sh
		echo -e "  ${INFO} Upgrading gravity database from version 5 to 6"
		sqlite3 "${database}" < "${scriptPath}/5_to_6.sql"
		version=6
	fi
	if [[ "$version" == "6" ]]; then
		# This migration script adds a special group with ID 0
		# which is automatically associated to all clients not
		# having their own group assignments
		echo -e "  ${INFO} Upgrading gravity database from version 6 to 7"
		sqlite3 "${database}" < "${scriptPath}/6_to_7.sql"
		version=7
	fi
	if [[ "$version" == "7" ]]; then
		# This migration script recreated the group table
		# to ensure uniqueness on the group name
		# We also add date_added and date_modified columns
		echo -e "  ${INFO} Upgrading gravity database from version 7 to 8"
		sqlite3 "${database}" < "${scriptPath}/7_to_8.sql"
		version=8
	fi
	if [[ "$version" == "8" ]]; then
		# This migration fixes some issues that were introduced
		# in the previous migration script.
		echo -e "  ${INFO} Upgrading gravity database from version 8 to 9"
		sqlite3 "${database}" < "${scriptPath}/8_to_9.sql"
		version=9
	fi
	if [[ "$version" == "9" ]]; then
		# This migration drops unused tables and creates triggers to remove
		# obsolete groups assignments when the linked items are deleted
		echo -e "  ${INFO} Upgrading gravity database from version 9 to 10"
		sqlite3 "${database}" < "${scriptPath}/9_to_10.sql"
		version=10
	fi
	if [[ "$version" == "10" ]]; then
		# This adds timestamp and an optional comment field to the client table
		# These fields are only temporary and will be replaces by the columns
		# defined in gravity.db.sql during gravity swapping. We add them here
		# to keep the copying process generic (needs the same columns in both the
		# source and the destination databases).
		echo -e "  ${INFO} Upgrading gravity database from version 10 to 11"
		sqlite3 "${database}" < "${scriptPath}/10_to_11.sql"
		version=11
	fi
	if [[ "$version" == "11" ]]; then
		# Rename group 0 from "Unassociated" to "Default"
		echo -e "  ${INFO} Upgrading gravity database from version 11 to 12"
		sqlite3 "${database}" < "${scriptPath}/11_to_12.sql"
		version=12
	fi
	if [[ "$version" == "12" ]]; then
		# Add column date_updated to alist table
		echo -e "  ${INFO} Upgrading gravity database from version 12 to 13"
		sqlite3 "${database}" < "${scriptPath}/12_to_13.sql"
		version=13
	fi
}
