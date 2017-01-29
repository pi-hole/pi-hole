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

. /etc/pihole/setupVars.conf

# Borrowed/modified from https://gist.github.com/cjus/1047794
function GetJSONValue {
    retVal=$(echo $1 | sed 's/\\\\\//\//g' | \
                       sed 's/[{}]//g' | \
                       awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | \
                       sed 's/\"\:/\|/g' | \
                       sed 's/[\,]/ /g' | \
                       sed 's/\"//g' | \
                       grep -w $2)
    echo ${retVal##*|}
}

outputJSON() {
	json=$(curl -s -X GET http://127.0.0.1/admin/api.php?summaryRaw)
	echo ${json}
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
		# Uncomment to continually read the log file and display the current domain being blocked
		#tail -f /var/log/pihole.log | awk '/\/etc\/pihole\/gravity.list/ {if ($7 != "address" && $7 != "name" && $7 != "/etc/pihole/gravity.list") print $7; else;}'

		json=$(curl -s -X GET http://127.0.0.1/admin/api.php?summaryRaw)

    domains=$(printf "%'.f" $(GetJSONValue ${json} "domains_being_blocked")) #add commas in
    queries=$(printf "%'.f" $(GetJSONValue ${json} "dns_queries_today"))
    blocked=$(printf "%'.f" $(GetJSONValue ${json} "ads_blocked_today"))
    LC_NUMERIC=C percentage=$(printf "%0.2f\n" $(GetJSONValue ${json} "ads_percentage_today")) #2 decimal places

		echo "Blocking:      ${domains}"
		echo "Queries:       ${queries}"

		echo "Pi-holed:      ${blocked} (${percentage}%)"

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
