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
		# This migration script upgrades the gravity and list views
		# implementing necessary changes for per-client blocking
		echo -e "  ${INFO} Upgrading gravity database from version 3 to 4"
		sqlite3 "${database}" < "${scriptPath}/3_to_4.sql"
		version=4
	fi
	if [[ "$version" == "4" ]]; then
		# This migration script upgrades the adlist view
		# to return an ID used in gravity.sh
		echo -e "  ${INFO} Upgrading gravity database from version 4 to 5"
		sqlite3 "${database}" < "${scriptPath}/4_to_5.sql"
		version=5
	fi
}
