#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Calculates stats and displays to an LCD
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.


#Functions##############################################################################################################
piLog="/var/log/pihole.log"
gravity="/etc/pihole/gravity.list"

today=$(date "+%b %e")

. /etc/pihole/setupVars.conf

CalcBlockedDomains() {
	if [ -e "${gravity}" ]; then
		#Are we IPV6 or IPV4?
		if [[ -n "${IPV6_ADDRESS}" ]]; then
			#We are IPV6
			blockedDomainsTotal=$(wc -l /etc/pihole/gravity.list | awk '{print $1/2}')
		else
			#We are IPV4
			blockedDomainsTotal=$(wc -l /etc/pihole/gravity.list | awk '{print $1}')
		fi
	else
		blockedDomainsTotal="Err."
	fi
}

CalcQueriesToday() {
	if [ -e "${piLog}" ]; then
		queriesToday=$(cat "${piLog}" | grep "${today}" | awk '/query/ {print $6}' | wc -l)
	else
		queriesToday="Err."
	fi
}

CalcblockedToday() {
	if [ -e "${piLog}" ] && [ -e "${gravity}" ];then
		blockedToday=$(cat ${piLog} | awk '/\/etc\/pihole\/gravity.list/ && !/address/ {print $6}' | wc -l)
	else
		blockedToday="Err."
	fi
}

CalcPercentBlockedToday() {
	if [ "${queriesToday}" != "Err." ] && [ "${blockedToday}" != "Err." ]; then
		if [ "${queriesToday}" != 0 ]; then #Fixes divide by zero error :)
			#scale 2 rounds the number down, so we'll do scale 4 and then trim the last 2 zeros
			percentBlockedToday=$(echo "scale=4; ${blockedToday}/${queriesToday}*100" | bc)
			percentBlockedToday=$(sed 's/.\{2\}$//' <<< "${percentBlockedToday}")
		else
			percentBlockedToday=0
		fi
	fi
}

outputJSON() {
	CalcQueriesToday
	CalcblockedToday
	CalcPercentBlockedToday

	CalcBlockedDomains

	printf '{"domains_being_blocked":"%s","dns_queries_today":"%s","ads_blocked_today":"%s","ads_percentage_today":"%s"}\n' "$blockedDomainsTotal" "$queriesToday" "$blockedToday" "$percentBlockedToday"
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
		echo "        $(ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -d':' -f2)"
		echo ""
		uptime | cut -d' ' -f11-
		#uptime -p	#Doesn't work on all versions of uptime
		uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes."}'
		echo "-------------------------------"
		# Uncomment to continually read the log file and display the current domain being blocked
		#tail -f /var/log/pihole.log | awk '/\/etc\/pihole\/gravity.list/ {if ($7 != "address" && $7 != "name" && $7 != "/etc/pihole/gravity.list") print $7; else;}'

		#uncomment next 4 lines to use original query count calculation
		#today=$(date "+%b %e")
		#todaysQueryCount=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ {print $7}' | wc -l)
		#todaysQueryCountV4=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ && /\[A\]/ {print $7}' | wc -l)
		#todaysQueryCountV6=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ && /\[AAAA\]/ {print $7}' | wc -l)


		CalcQueriesToday
		CalcblockedToday
		CalcPercentBlockedToday

		CalcBlockedDomains

		echo "Blocking:      ${blockedDomainsTotal}"
		#below commented line does not add up to todaysQueryCount
		#echo "Queries:       $todaysQueryCountV4 / $todaysQueryCountV6"
		echo "Queries:       ${queriesToday}" #same total calculation as dashboard
	  echo "Pi-holed:      ${blockedToday} (${percentBlockedToday}%)"

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
    exit 1
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
