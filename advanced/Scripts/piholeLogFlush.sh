#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Flushes /var/log/pihole.log
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Check if pihole user, and if not then rerun with sudo.
echo ":::"
runninguser=$(whoami)
if [[ "$runninguser" = "pihole"  ]];then
	echo "::: You are pihole user."
	# Older versions of Pi-hole set $SUDO="sudo" and prefixed commands with it,
	# rather than rerunning as sudo. Just in case it turns up by accident, 
	# explicitly set the $SUDO variable to an empty string.
	SUDO=""
else
	echo "::: sudo will be used."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [[ $(dpkg-query -s sudo) ]];then
		echo "::: Running sudo -u pihole $0 $@"
		sudo -u pihole "$0" "$@"
		exit $?
	else
		echo "::: Please install sudo."
	exit 1
	fi
fi

truncate -s 0 /var/log/pihole.log
