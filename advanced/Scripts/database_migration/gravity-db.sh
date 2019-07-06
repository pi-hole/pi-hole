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
	local version
	version="$(sqlite3 "$1" "SELECT \"value\" FROM \"info\" WHERE \"property\" = 'version';")"

	if [[ "$version" == "1" ]]; then
		sqlite3 "$1" < "/etc/.pihole/advanced/Scripts/database_migration/gravity/1_to_2.sql"
		version=2
	fi
}
