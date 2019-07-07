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
	local database auditFile version
	database="${1}"
	auditFile="${2}"
	version="$(sqlite3 "${database}" "SELECT \"value\" FROM \"info\" WHERE \"property\" = 'version';")"

	if [[ "$version" == "1" ]]; then
		# This migration script upgrades the gravity.db file by
		# adding the domain_auditlist table
		sqlite3 "${database}" < "/etc/.pihole/advanced/Scripts/database_migration/gravity/1_to_2.sql"
		version=2

		# Store audit domains in database table
		if [ -e "${auditFile}" ]; then
			echo -e "  ${INFO} Migrating content of ${auditFile} into new database"
			# database_table_from_file is defined in gravity.sh
			database_table_from_file "domain_auditlist" "${auditFile}"
		fi
	fi
}
