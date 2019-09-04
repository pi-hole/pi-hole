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
		sqlite3 "${database}" < "/etc/.pihole/advanced/Scripts/database_migration/gravity/1_to_2.sql"
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
		sqlite3 "${database}" < "/etc/.pihole/advanced/Scripts/database_migration/gravity/2_to_3.sql"
		version=3
	fi
	if [[ "$version" == "3" ]]; then
		# This migration script upgrades ...
		sqlite3 "${database}" < "/etc/.pihole/advanced/Scripts/database_migration/gravity/3_to_4.sql"
		version=3
	fi
}
