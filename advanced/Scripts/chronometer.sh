#!/bin/bash
# Infinite loop that can be used to display ad domains on a Pi touch screen
# Continually watch the log file and display ad domains that are blocked being blocked
# Set the pi user to log in automatically and add run this script from .bashrc
clear
echo ""
echo "       +-+-+-+-+-+-+-+ "
echo "           Pi-hole     "
echo "       +-+-+-+-+-+-+-+ "
echo ""
echo "       A black hole for"
echo "        Internet Ads   " 
echo ""
echo "     http://pi-hole.net"
echo ""
echo "     $(ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -d':' -f2)"
sleep 7
# Look for only the entries that contain /etc/hosts, indicating the domain was found to be an advertisement
tail -f /var/log/daemon.log | awk '/\/etc\/hosts/ {if ($7 != "address" && $7 != "name" && $7 != "/etc/hosts") print $7; else;}'