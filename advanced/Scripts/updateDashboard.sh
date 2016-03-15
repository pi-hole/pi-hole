#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Updates the Pi-hole web interface
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

source /etc/pihole/Functions/pihole.var
source /etc/pihole/Functions/pihole.funcs
source /etc/pihole/Functions/git.funcs

main() {
    prerequisites
    if ! is_repo $webInterfaceDir; then
        make_repo $webInterfaceDir $webInterfaceGitUrl
    fi
    update_repo $webInterfaceDir
}

prerequisites() {
	# must be root to update
	if [[ $EUID -ne 0 ]]; then
		sudo bash "$0" "$@"
		exit $?
	fi
	
	# web interface must already exist. this is a (lazy)
	# check to make sure pihole is actually installed.
	if [ ! -d "$webInterfaceDir" ]; then
		echo "$webInterfaceDir not found. Exiting."
		exit 1
	fi
	
	if ! type "git" > /dev/null; then
		apt-get -y install git
	fi
}

main
