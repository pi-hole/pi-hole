#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Completely uninstalls Pi-hole
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Must be root to uninstall
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: Sudo will be used for the uninstall."
  # Check if it is actually installed
  # If it isn't, exit because the unnstall cannot complete
  if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
  else
    echo "::: Please install sudo or run this as root."
    exit 1
  fi
fi

spinner()
{
    local pid=$1
    local delay=0.50
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

function removeAndPurge {
	# Purge dependencies
echo ":::"
	# Nate 3/28/2016 - Removed `php5-cgi` and `php5` as they are removed with php5-common
	dependencies=( dnsutils bc toilet figlet dnsmasq lighttpd php5-common git curl unzip wget )
	for i in "${dependencies[@]}"; do
		if [ "$(dpkg-query -W --showformat='${Status}\n' "$i" 2> /dev/null | grep -c "ok installed")" -eq 1 ]; then
			while true; do
				read -rp "::: Do you wish to remove $i from your system? [y/n]: " yn
				case $yn in
					[Yy]* ) printf ":::\tRemoving %s..." "$i"; $SUDO apt-get -y remove --purge "$i" &> /dev/null & spinner $!; printf "done!\n"; break;;
					[Nn]* ) printf ":::\tSkipping %s" "$i"; break;;
					* ) printf "::: You must answer yes or no!";;
				esac
			done
		else
			printf ":::\tPackage %s not installed... Not removing.\n" "$i"
		fi
	done

	# Remove dependency config files
	echo "::: Removing dnsmasq config files..."
	$SUDO rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/01-pihole.conf &> /dev/null

	# Take care of any additional package cleaning
	printf "::: Auto removing remaining dependencies..."
	$SUDO apt-get -y autoremove &> /dev/null & spinner $!; printf "done!\n";
	printf "::: Auto cleaning remaining dependencies..."
	$SUDO apt-get -y autoclean &> /dev/null & spinner $!; printf "done!\n";

	# Call removeNoPurge to remove PiHole specific files
	removeNoPurge
}

function removeNoPurge {
	echo ":::"
	# Only web directories/files that are created by pihole should be removed.
	echo "::: Removing the Pi-hole Web server files..."
	$SUDO rm -rf /var/www/html/admin &> /dev/null
	$SUDO rm -rf /var/www/html/pihole &> /dev/null
	$SUDO rm /var/www/html/index.lighttpd.orig &> /dev/null

	# If the web directory is empty after removing these files, then the parent html folder can be removed.
	if [ -d "/var/www/html" ]; then
		if [[ ! "$(ls -A /var/www/html)" ]]; then
    			$SUDO rm -rf /var/www/html &> /dev/null
		fi
	fi

	# Attempt to preserve backwards compatibility with older versions
	# to guarantee no additional changes were made to /etc/crontab after
	# the installation of pihole, /etc/crontab.pihole should be permanently
	# preserved.
	if [[ -f /etc/crontab.orig ]]; then
		echo "::: Initial Pi-hole cron detected.  Restoring the default system cron..."
		$SUDO mv /etc/crontab /etc/crontab.pihole
		$SUDO mv /etc/crontab.orig /etc/crontab
		$SUDO service cron restart
	fi

	# Attempt to preserve backwards compatibility with older versions
	if [[ -f /etc/cron.d/pihole ]];then
		echo "::: Removing cron.d/pihole..."
		$SUDO rm /etc/cron.d/pihole &> /dev/null
	fi

	echo "::: Removing config files and scripts..."
	$SUDO rm -rf /etc/lighttpd/ &> /dev/null
	$SUDO rm /var/log/pihole.log &> /dev/null
	$SUDO rm /usr/local/bin/gravity.sh &> /dev/null
	$SUDO rm /usr/local/bin/chronometer.sh &> /dev/null
	$SUDO rm /usr/local/bin/whitelist.sh &> /dev/null
	$SUDO rm /usr/local/bin/piholeLogFlush.sh &> /dev/null
	$SUDO rm /usr/local/bin/piholeDebug.sh &> /dev/null
	$SUDO rm /usr/local/bin/updateDashboard.sh &> /dev/null
	$SUDO rm /usr/local/bin/uninstall.sh &> /dev/null
	$SUDO rm /etc/dnsmasq.d/adList.conf &> /dev/null
	$SUDO rm -rf /var/log/*pihole* &> /dev/null
	$SUDO rm -rf /etc/pihole/ &> /dev/null
	$SUDO rm -rf /etc/.pihole/ &> /dev/null
	$SUDO rm -rf /opt/pihole/ &> /dev/null
	
	echo ":::"
	printf "::: Finished removing PiHole from your system. Sorry to see you go!\n"
	printf "::: Reach out to us at https://github.com/pi-hole/pi-hole/issues if you need help\n"
	printf "::: Reinstall by simpling running\n:::\n:::\tcurl -L install.pi-hole.net | bash\n:::\n::: at any time!\n:::\n"
	printf "::: PLEASE RESET YOUR DNS ON YOUR ROUTER/CLIENTS TO RESTORE INTERNET CONNECTIVITY!\n"
}

######### SCRIPT ###########
echo "::: Preparing to remove packages, be sure that each may be safely removed depending on your operating system."
echo "::: (SAFE TO REMOVE ALL ON RASPBIAN)"
while true; do
	read -rp "::: Do you wish to purge PiHole's dependencies from your OS? (You will be prompted for each package) [y/n]: " yn
	case $yn in
		[Yy]* ) removeAndPurge; break;;
	
		[Nn]* ) removeNoPurge; break;;
	esac
done


