#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Calculates stats and displays to an LCD
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

#Functions##############################################################################################################
piLog="/var/log/pihole.log"
gravity="/etc/pihole/gravity.list"

. /etc/pihole/setupVars.conf

function GetFTLData {
    # Open connection to FTL
    exec 3<>/dev/tcp/localhost/"$(cat /var/run/pihole-FTL.port)"

    # Test if connection is open
    if { >&3; } 2> /dev/null; then
       # Send command to FTL
       echo -e ">$1" >&3

       # Read input
       read -r -t 1 LINE <&3
       until [ ! $? ] || [[ "$LINE" == *"EOM"* ]]; do
           echo "$LINE" >&1
           read -r -t 1 LINE <&3
       done

       # Close connection
       exec 3>&-
       exec 3<&-
   fi
}

outputJSON() {
	get_summary_data
	echo "{\"domains_being_blocked\":${domains_being_blocked_raw},\"dns_queries_today\":${dns_queries_today_raw},\"ads_blocked_today\":${ads_blocked_today_raw},\"ads_percentage_today\":${ads_percentage_today_raw}"
}

get_summary_data() {
	local summary=$(GetFTLData "stats")
	domains_being_blocked_raw=$(grep "domains_being_blocked" <<< "${summary}" | grep -Eo "[0-9]+$")
	domains_being_blocked=$(printf "%'.f" ${domains_being_blocked_raw})
	dns_queries_today_raw=$(grep "dns_queries_today" <<< "$summary" | grep -Eo "[0-9]+$")
	dns_queries_today=$(printf "%'.f" ${dns_queries_today_raw})
	ads_blocked_today_raw=$(grep "ads_blocked_today" <<< "$summary" | grep -Eo "[0-9]+$")
	ads_blocked_today=$(printf "%'.f" ${ads_blocked_today_raw})
	ads_percentage_today_raw=$(grep "ads_percentage_today" <<< "$summary" | grep -Eo "[0-9.]+$")
	LC_NUMERIC=C ads_percentage_today=$(printf "%'.f" ${ads_percentage_today_raw})
}

normalChrono() {
	for (( ; ; )); do
		clear
		# Displays a colorful Pi-hole logo
		echo " [0;1;35;95m_[0;1;31;91m__[0m [0;1;33;93m_[0m     [0;1;34;94m_[0m        [0;1;36;96m_[0m"
		echo "[0;1;31;91m|[0m [0;1;33;93m_[0m [0;1;32;92m(_[0;1;36;96m)_[0;1;34;94m__[0;1;35;95m|[0m [0;1;31;91m|_[0m  [0;1;32;92m__[0;1;36;96m_|[0m [0;1;34;94m|[0;1;35;95m__[0;1;31;91m_[0m"
		echo "[0;1;33;93m|[0m  [0;1;32;92m_[0;1;36;96m/[0m [0;1;34;94m|_[0;1;35;95m__[0;1;31;91m|[0m [0;1;33;93m'[0m [0;1;32;92m\/[0m [0;1;36;96m_[0m [0;1;34;94m\[0m [0;1;35;95m/[0m [0;1;31;91m-[0;1;33;93m_)[0m"
		echo "[0;1;32;92m|_[0;1;36;96m|[0m [0;1;34;94m|_[0;1;35;95m|[0m   [0;1;33;93m|_[0;1;32;92m||[0;1;36;96m_\[0;1;34;94m__[0;1;35;95m_/[0;1;31;91m_\[0;1;33;93m__[0;1;32;92m_|[0m"
		echo ""
		echo "        ${IPV4_ADDRESS}"
		echo ""
		uptime | cut -d' ' -f11-
		#uptime -p	#Doesn't work on all versions of uptime
		uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes."}'
		echo "-------------------------------"
		domain=$(GetFTLData recentBlocked)
		echo "Recently blocked:"
		echo "  $domain"

		get_summary_data
		echo "Blocking:      ${domains_being_blocked}"
		echo "Queries:       ${dns_queries_today}"
		echo "Pi-holed:      ${ads_blocked_today} (${ads_percentage_today}%)"

		sleep 5
	done
}

displayHelp() {
	cat << EOM
::: Displays stats about your piHole!
:::
::: Usage: sudo pihole -c [optional:-j]
::: Note: If no option is passed, then stats are displayed on screen, updated every 5 seconds
:::
::: Options:
:::  -j, --json		output stats as JSON formatted string
:::  -h, --help		display this help text
EOM
    exit 0
}

if [[ $# = 0 ]]; then
	normalChrono
fi

for var in "$@"; do
	case "$var" in
		"-j" | "--json"  ) outputJSON;;
		"-h" | "--help"  ) displayHelp;;
		*                ) exit 1;;
	esac
done
