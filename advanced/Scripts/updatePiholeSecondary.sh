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

stopServices() {
	# Stop dnsmasq and lighttpd
	echo ":::"
	echo -n "::: Stopping services..."
	$SUDO service lighttpd stop
	echo " done."
}

installScripts() {
	# Install the scripts from /etc/.pihole to their various locations
	echo ":::"
	echo -n "::: Updating scripts in /opt/pihole..."

	$SUDO cp /etc/.pihole/gravity.sh /opt/pihole/gravity.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/chronometer.sh /opt/pihole/chronometer.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/whitelist.sh /opt/pihole/whitelist.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/blacklist.sh /opt/pihole/blacklist.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/piholeDebug.sh /opt/pihole/piholeDebug.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/piholeLogFlush.sh /opt/pihole/piholeLogFlush.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/updateDashboard.sh /opt/pihole/updateDashboard.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/updatePihole.sh /opt/pihole/updatePihole.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/updatePiholeSecondary.sh /opt/pihole/updatePiholeSecondary.sh
	$SUDO cp /etc/.pihole/automated\ install/uninstall.sh /opt/pihole/uninstall.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/setupLCD.sh /opt/pihole/setupLCD.sh
	$SUDO chmod 755 /opt/pihole/{gravity,chronometer,whitelist,blacklist,piholeLogFlush,updateDashboard,updatePihole,updatePiholeSecondary,uninstall,setupLCD, piholeDebug}.sh
	$SUDO cp /etc/.pihole/pihole /usr/local/bin/pihole
	$SUDO chmod 755 /usr/local/bin/pihole
	$SUDO cp /etc/.pihole/advanced/bash-completion/pihole /etc/bash_completion.d/pihole
	. /etc/bash_completion.d/pihole

	#Tidy up /usr/local/bin directory if updating an old installation (can probably be removed at some point)
	oldFiles=( gravity chronometer whitelist blacklist piholeLogFlush updateDashboard updatePihole updatePiholeSecondary uninstall setupLCD piholeDebug)
	for i in "${oldFiles[@]}"; do
		if [ -f "/usr/local/bin/$i.sh" ]; then
			$SUDO rm /usr/local/bin/"$i".sh
		fi
	done

	echo " done."
}


########################
# SCRIPT STARTS HERE! #
#######################

#uncomment the below if adding new dependencies (don't forget to update the install script!)
#updateDependencies
stopServices
installScripts

#TODO:
# - Distribute files`
# - Run pihole -g
# - add root check, maybe? Do we need to? Probably a good idea.
# - update install script to populate a config file with:
#       -IPv4
#       -IPv6
#       -UpstreamDNS servers
