#!/bin/bash
# Displays Pi-hole stats on the Adafruit PiTFT 2.8" touch screen
# Set the pi user to log in automatically and run this script from /etc/profile
for (( ; ; ))
do
	clear
	# Displays a colorful Pi-hole logo
	toilet -f small -F gay Pi-hole
	echo "        $(ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -d':' -f2)"
	echo ""
	uptime | cut -d' ' -f11-
	echo "-------------------------------"
	# Uncomment to continually read the log file and display the current domain being blocked
	#tail -f /var/log/pihole.log | awk '/\/etc\/pihole\/gravity.list/ {if ($7 != "address" && $7 != "name" && $7 != "/etc/pihole/gravity.list") print $7; else;}'
	
	today=$(date "+%b %e")
	todaysQueryCount=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ {print $7}' | wc -l)
	todaysQueryCountV4=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ && /\[A\]/ {print $7}' | wc -l)
	todaysQueryCountV6=$(cat /var/log/pihole.log | grep "$today" | awk '/query/ && /\[AAAA\]/ {print $7}' | wc -l)
	todaysAdsEliminated=$(cat /var/log/pihole.log | grep "$today" | awk '/\/etc\/pihole\/gravity.list/ {print $7}' | wc -l)
	dividend=$(echo "$todaysAdsEliminated/$todaysQueryCount" | bc -l)
	fp=$(echo "$dividend*100" | bc -l)
	percentAds=$(echo ${fp:0:4})
	
	echo "Queries:       $todaysQueryCountV4 / $todaysQueryCountV6"
	echo "Pi-holed:      $todaysAdsEliminated  ($percentAds%)"
	sleep 5
done
