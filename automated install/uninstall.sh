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


spinner() {
	local pid=$1

	spin='-\|/'
	i=0
	while $SUDO kill -0 $pid 2>/dev/null
	do
		i=$(( (i+1) %4 ))
		printf "\b${spin:$i:1}"
		sleep .1
	done
	printf "\b"
}

echo ":::"
echo "::: Sorry to see you go :(..."
echo ":::"
# Must be root to uninstall
if [[ $EUID -eq 0 ]];then
	echo "You are root."
else
	echo "::: sudo will be used for the uninstall."
  # Check if it is actually installed
  # If it isn't, exit because the unnstall cannot complete
  if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
  else
    echo "Please install sudo or run this as root."
    exit 1
  fi
fi


######### SCRIPT ###########
#Check with user which dependencies to remove. They may be using some of them elsewhere
echo ":::"
echo "::: Removing dependencies..."
dependencies=( dnsutils bc toilet figlet dnsmasq lighttpd php5-common php5-cgi php5 git curl unzip wget )
	for i in "${dependencies[@]}"
	do
	:
		if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
			while true; do
			    read -p ":::     Do you wish to remove this dependency from your system? [$i] (y/n): " yn
			    case $yn in
			        [Yy]* ) echo -n ":::        removing $i....";$SUDO apt-get -y -qq remove $i > /dev/null & spinner $!; echo " done."; break;;
			        [Nn]* ) echo ":::        Keeping $i installed"; break;;
			        * ) echo ":::         Please answer yes or no.";;
			    esac			    
			done
			echo ":::"
		fi
	done

# Only web directories/files that are created by pihole should be removed.
echo -n "::: Removing the Pi-hole Web server files..."
$SUDO rm -rf /var/www/html/admin
$SUDO rm -rf /var/www/html/pihole
$SUDO rm /var/www/html/index.lighttpd.orig
echo " done."

echo ":::"
echo -n "::: Removing PiHole Git Directory..."
$SUDO rm -rf /etc/.pihole
echo " done."

# If the web directory is empty after removing these files, then the parent html folder can be removed.
#if [[ ! "$(ls -A /var/www/html)" ]]; then
#    $SUDO rm -rf /var/www/html
#fi

echo -n "::: Removing pi-hole dnsmasq config file..."
$SUDO rm /etc/dnsmasq.d/01-pihole.conf
echo " done."

# Attempt to preserve backwards compatibility with older versions
# to guarantee no additional changes were made to /etc/crontab after
# the installation of pihole, /etc/crontab.pihole should be permanently
# preserved.
if [[ -f /etc/crontab.orig ]]; then
  echo "Initial Pi-hole cron detected.  Restoring the default system cron..."
	$SUDO mv /etc/crontab /etc/crontab.pihole
	$SUDO mv /etc/crontab.orig /etc/crontab
	$SUDO service cron restart
fi

# Attempt to preserve backwards compatibility with older versions
if [[ -f /etc/cron.d/pihole ]];then
  echo -n "::: Removing pi-hole cron jobs..."
	$SUDO rm /etc/cron.d/pihole
	echo " done."
fi

echo -n "::: Removing config files and scripts..."
$SUDO rm -rf /etc/.pihole/
#$SUDO rm -rf /etc/lighttpd/
$SUDO rm /var/log/pihole.log
$SUDO rm /usr/local/bin/gravity.sh
$SUDO rm /usr/local/bin/chronometer.sh
$SUDO rm /usr/local/bin/whitelist.sh
$SUDO rm /usr/local/bin/blacklist.sh
$SUDO rm /usr/local/bin/piholeLogFlush.sh
$SUDO rm -rf /etc/pihole/
$SUDO rm /usr/local/bin/uninstall.sh
echo " done."
