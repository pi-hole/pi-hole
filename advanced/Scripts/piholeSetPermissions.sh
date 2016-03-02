#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Sets permissions to pihole files and directories
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Check if root, and if not then rerun with sudo.
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
	# Older versions of Pi-hole set $SUDO="sudo" and prefixed commands with it,
	# rather than rerunning as sudo. Just in case it turns up by accident, 
	# explicitly set the $SUDO variable to an empty string.
	SUDO=""
else
	echo "::: sudo will be used."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [[ $(dpkg-query -s sudo) ]];then
		echo "::: Running sudo $@"
		sudo "$@"
		exit $?
	else
		echo "::: Please install sudo or run this script as root."
	exit 1
	fi
fi

chown --recursive root:pihole /etc/pihole
chmod --recursive ug=rwX,o=rX /etc/pihole
