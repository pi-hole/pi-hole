#!/bin/bash
# Infinite loop that can be used to display ad domains on a Pi touch screen
# It will continually display ads that are blocked in real time on the screen
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
echo "  Pi-hole IP: $(ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -d':' -f2)"
echo ""
echo "Ads blocked will show up once"
echo "you set your DNS server."
echo ""
sleep 7
tail -f /var/log/daemon.log | awk '/\/etc\/hosts/ {if ($7 != "address" && $7 != "name" && $7 != "/etc/hosts") print $7; else;}'