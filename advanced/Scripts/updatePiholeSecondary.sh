#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Checks if Pi-hole needs updating and then
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Must be root to use this tool
if [[ ! $EUID -eq 0 ]];then
	#echo "::: You are root."
#else
	#echo "::: Sudo will be used for this tool."
  # Check if it is actually installed
  # If it isn't, exit because the pihole cannot be invoked without privileges.
  if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
  else
    echo "::: Please install sudo or run this as root."
    exit 1
  fi
fi

function updateDependencies(){
	#Add any new dependencies to the below array`
	newDependencies=()
	echo "::: Installing any new dependencies..."
	for i in "${newDependencies[@]}"; do
		echo "checking for $i"
		if [ "$(dpkg-query -W -f='${Status}' "$i" 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
			echo -n " Not found! Installing...."
			$SUDO apt-get -y -qq install "$i" > /dev/null & spinner $!
			echo " done!"
		else
			echo " already installed!"
		fi
	done
	}
}

#uncomment the below if adding new dependencies (don't forget to update the install script!)
#updateDependencies



#TODO:
# - Distribute files`
# - Run pihole -g
# - add root check, maybe? Do we need to? Probably a good idea.
