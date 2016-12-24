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
if [[ ${EUID} -eq 0 ]]; then
	echo "::: You are root."
else
	echo "::: Sudo will be used for the uninstall."
	# Check if it is actually installed
	# If it isn't, exit because the unnstall cannot complete
	if [ -x "$(command -v sudo)" ]; then
		export SUDO="sudo"
	else
		echo "::: Please install sudo or run this as root."
		exit 1
	fi
fi

# Compatability
if [ -x "$(command -v rpm)" ]; then
	# Fedora Family
	if [ -x "$(command -v dnf)" ]; then
		PKG_MANAGER="dnf"
	else
		PKG_MANAGER="yum"
	fi
	PKG_REMOVE="${PKG_MANAGER} remove -y"
	PIHOLE_DEPS=( bind-utils bc dnsmasq lighttpd lighttpd-fastcgi php-common git curl unzip wget findutils )
	package_check() {
		rpm -qa | grep ^$1- > /dev/null
	}
	package_cleanup() {
		${SUDO} ${PKG_MANAGER} -y autoremove
	}
elif [ -x "$(command -v apt-get)" ]; then
	# Debian Family
	PKG_MANAGER="apt-get"
	PKG_REMOVE="${PKG_MANAGER} -y remove --purge"
	PIHOLE_DEPS=( dnsutils bc dnsmasq lighttpd php5-common git curl unzip wget )
	package_check() {
		dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
	}
	package_cleanup() {
		${SUDO} ${PKG_MANAGER} -y autoremove
		${SUDO} ${PKG_MANAGER} -y autoclean
	}
else
	echo "OS distribution not supported"
	exit
fi

spinner() {
	local pid=$1
	local delay=0.50
	local spinstr='/-\|'
	while [ "$(ps a | awk '{print $1}' | grep "${pid}")" ]; do
		local temp=${spinstr#?}
		printf " [%c]  " "${spinstr}"
		local spinstr=${temp}${spinstr%"$temp}"}
		sleep ${delay}
		printf "\b\b\b\b\b\b"
	done
	printf "    \b\b\b\b"
}

removeAndPurge() {
	# Purge dependencies
	echo ":::"
	for i in "${PIHOLE_DEPS[@]}"; do
		package_check ${i} > /dev/null
		if [ $? -eq 0 ]; then
			while true; do
				read -rp "::: Do you wish to remove ${i} from your system? [y/n]: " yn
				case ${yn} in
					[Yy]* ) printf ":::\tRemoving %s..." "${i}"; ${SUDO} ${PKG_REMOVE} "${i}" &> /dev/null & spinner $!; printf "done!\n"; break;;
					[Nn]* ) printf ":::\tSkipping %s\n" "${i}"; break;;
					* ) printf "::: You must answer yes or no!\n";;
				esac
			done
		else
			printf ":::\tPackage %s not installed... Not removing.\n" "${i}"
		fi
	done

	# Remove dependency config files
	echo "::: Removing dnsmasq config files..."
	${SUDO} rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/01-pihole.conf &> /dev/null

	# Take care of any additional package cleaning
	printf "::: Auto removing & cleaning remaining dependencies..."
	package_cleanup &> /dev/null & spinner $!; printf "done!\n";

	# Call removeNoPurge to remove PiHole specific files
	removeNoPurge
}

removeNoPurge() {
	echo ":::"
	# Only web directories/files that are created by pihole should be removed.
	echo "::: Removing the Pi-hole Web server files..."
	${SUDO} rm -rf /var/www/html/admin &> /dev/null
	${SUDO} rm -rf /var/www/html/pihole &> /dev/null
	${SUDO} rm /var/www/html/index.lighttpd.orig &> /dev/null

	# If the web directory is empty after removing these files, then the parent html folder can be removed.
	if [ -d "/var/www/html" ]; then
		if [[ ! "$(ls -A /var/www/html)" ]]; then
    			${SUDO} rm -rf /var/www/html &> /dev/null
		fi
	fi

	# Attempt to preserve backwards compatibility with older versions
	# to guarantee no additional changes were made to /etc/crontab after
	# the installation of pihole, /etc/crontab.pihole should be permanently
	# preserved.
	if [[ -f /etc/crontab.orig ]]; then
		echo "::: Initial Pi-hole cron detected.  Restoring the default system cron..."
		${SUDO} mv /etc/crontab /etc/crontab.pihole
		${SUDO} mv /etc/crontab.orig /etc/crontab
		${SUDO} service cron restart
	fi

	# Attempt to preserve backwards compatibility with older versions
	if [[ -f /etc/cron.d/pihole ]];then
		echo "::: Removing cron.d/pihole..."
		${SUDO} rm /etc/cron.d/pihole &> /dev/null
	fi

	echo "::: Removing config files and scripts..."
	package_check lighttpd > /dev/null
	if [ $? -eq 1 ]; then
		${SUDO} rm -rf /etc/lighttpd/ &> /dev/null
	else
		if [ -f /etc/lighttpd/lighttpd.conf.orig ]; then
			${SUDO} mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf
		fi
	fi

	${SUDO} rm /etc/dnsmasq.d/adList.conf &> /dev/null
	${SUDO} rm /etc/dnsmasq.d/01-pihole.conf &> /dev/null
	${SUDO} rm -rf /var/log/*pihole* &> /dev/null
	${SUDO} rm -rf /etc/pihole/ &> /dev/null
	${SUDO} rm -rf /etc/.pihole/ &> /dev/null
	${SUDO} rm -rf /opt/pihole/ &> /dev/null
	${SUDO} rm /usr/local/bin/pihole &> /dev/null
	${SUDO} rm /etc/bash_completion.d/pihole &> /dev/null
	${SUDO} rm /etc/sudoers.d/pihole &> /dev/null
	
	# If the pihole user exists, then remove
	if id "pihole" >/dev/null 2>&1; then
        	echo "::: Removing pihole user..."
		${SUDO} userdel -r pihole
	fi

	echo ":::"
	printf "::: Finished removing PiHole from your system. Sorry to see you go!\n"
	printf "::: Reach out to us at https://github.com/pi-hole/pi-hole/issues if you need help\n"
	printf "::: Reinstall by simpling running\n:::\n:::\tcurl -L https://install.pi-hole.net | bash\n:::\n::: at any time!\n:::\n"
	printf "::: PLEASE RESET YOUR DNS ON YOUR ROUTER/CLIENTS TO RESTORE INTERNET CONNECTIVITY!\n"
}

######### SCRIPT ###########
echo "::: Preparing to remove packages, be sure that each may be safely removed depending on your operating system."
echo "::: (SAFE TO REMOVE ALL ON RASPBIAN)"
while true; do
	read -rp "::: Do you wish to purge PiHole's dependencies from your OS? (You will be prompted for each package) [y/n]: " yn
	case ${yn} in
		[Yy]* ) removeAndPurge; break;;
	
		[Nn]* ) removeNoPurge; break;;
	esac
done
