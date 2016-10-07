#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Generates pihole_debug.log to be used for troubleshooting.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

set -o pipefail

######## GLOBAL VARS ########
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
PIHOLECONFFILE="/etc/dnsmasq.d/01-pihole.conf"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
HOSTSFILE="/etc/hosts"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTSFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
WHITELISTMATCHES="/tmp/whitelistmatches.list"

# Header info and introduction
echo "::: Beginning Pi-hole debug at $(date)!"
echo "::: This debugging process will collect information from your running configuration,"
echo "::: and optionally upload the generated log to a unique and random directory on"
echo "::: Termbin.com. NOTE: All log files auto-delete after 1 month and you are the only"
echo "::: person who is given the unique URL. Please consider where you post this link."
echo "::: "


######## FIRST CHECK ########
# Must be root to debug
if [[ "$EUID" -eq 0 ]]; then
	echo "::: Script is executing as root user..."
else
	echo "::: Non-root user detected..."
	# Check if sudo is actually installed
	if [ -x "$(command -v sudo)" ]; then
		export SUDO="sudo"
		echo "::: sudo command located, debug will run under sudo."
	else
		echo "::: Unable to locate sudo command. Please install sudo or run this as root."
		exit 1
	fi
fi

# Ensure the file exists, create if not, clear if exists.
if [ ! -f "$DEBUG_LOG" ]; then
	${SUDO} touch ${DEBUG_LOG}
	${SUDO} chmod 644 ${DEBUG_LOG}
	${SUDO} chown "$USER":root ${DEBUG_LOG}
else 
	truncate -s 0 ${DEBUG_LOG}
fi

### Private functions exist here ###
function log_write {
  echo "$1" >> "${DEBUG_LOG}"
}

function version_check {
  log_write "############################################################"
  log_write "##########           Installed Versions           ##########"
  log_write "############################################################"

  echo "::: Detecting Pi-hole installed versions."
  pi_hole_ver="$(cd /etc/.pihole/ && git describe --tags --abbrev=0)" \
  && log_write "Pi-hole Version: $pi_hole_ver" || log_write "Pi-hole git repository not detected."
  admin_ver="$(cd /var/www/html/admin && git describe --tags --abbrev=0)" \
  && log_write "WebUI Version: $admin_ver" || log_write "Pi-hole Admin Pages git repository not detected."

  echo "::: Writing lighttpd version to logfile."
  light_ver="$(lighttpd -v |& head -n1)" && log_write "${light_ver}" || log_write "lighttpd not installed."

  echo "::: Writing PHP version to logfile."
  php_ver="$(php -v |& head -n1)" && log_write "${php_ver}" || log_write "PHP not installed."
}

function distro_check {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "########          Installed OS Distribution        #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

	echo "::: Checking installed OS Distribution release."
	TMP=$(cat /etc/*release || echo "Failed to find release")

	echo "::: Writing OS Distribution release to logfile."
	echo "$TMP" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
}

function ip_check {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "########           IP Address Information          #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

    echo "::: Writing local IPs to logfile"
    IPADDR="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')"
    echo "$IPADDR" >> ${DEBUG_LOG}

    IP6ADDR="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')" \
    && echo "$IP6ADDR" >> ${DEBUG_LOG} || echo "No IPv6 addresses found." >> ${DEBUG_LOG}
    echo >> ${DEBUG_LOG}

    echo "::: Locating default gateway and checking connectivity"
    GATEWAY=$(ip r | grep default | cut -d ' ' -f 3)
    if [[ $? = 0 ]]
    then
    echo "::: Pinging default IPv4 gateway..."
    GATEWAY_CHECK=$(ping -q -w 3 -c 3 -n "${GATEWAY}" | tail -n3)
        if [[ $? = 0 ]]
        then
        echo "IPv4 Gateway check:" >> ${DEBUG_LOG}
        else
        echo "IPv4 Gateway check failed:" >> ${DEBUG_LOG}
        fi
    echo "$GATEWAY_CHECK" >> ${DEBUG_LOG}
    echo >> ${DEBUG_LOG}

    echo "::: Pinging Internet via IPv4..."
    INET_CHECK=$(ping -q -w 5 -c 3 -n 8.8.8.8 | tail -n3)
        if [[ $? = 0 ]]
        then
        echo "IPv4 Internet check:" >> ${DEBUG_LOG}
        else
        echo "IPv4 Internet check failed:" >> ${DEBUG_LOG}
        fi
    echo "$INET_CHECK" >> ${DEBUG_LOG}
    echo >> ${DEBUG_LOG}
    fi

    GATEWAY6=$(ip -6 r | grep default | cut -d ' ' -f 3)
    if [[ $? = 0 ]]
    then
    echo "::: Pinging default IPv6 gateway..."
    GATEWAY6_CHECK=$(ping6 -q -w 3 -c 3 -n "${GATEWAY6}" | tail -n3)
        if [[ $? = 0 ]]
        then
        echo "IPv6 Gateway check:" >> ${DEBUG_LOG}
        else
        echo "IPv6 Gateway check failed:" >> ${DEBUG_LOG}
        fi

    echo "::: Pinging Internet via IPv6..."
    GATEWAY6_CHECK=$(ping6 -q -w 3 -c 3 -n 2001:4860:4860::8888 | tail -n3)
        if [[ $? = 0 ]]
        then
        echo "IPv6 Internet check:" >> ${DEBUG_LOG}
        else
        echo "IPv6 Internet check failed:" >> ${DEBUG_LOG}
        fi

    else
    GATEWAY_CHECK="No IPv6 Gateway Detected"
    fi
    echo "$GATEWAY_CHECK" >> ${DEBUG_LOG}


    echo >> ${DEBUG_LOG}
}

function hostnameCheck {
    echo "############################################################" >> ${DEBUG_LOG}
	echo "########            Hostname Information           #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

    echo "::: Writing locally configured hostnames to logfile"
    # Write the hostname output to compare against entries in /etc/hosts, which is logged next
    echo "This Pi-hole is: $(hostname)" >> ${DEBUG_LOG}

    echo "::: Writing hosts file to debug log..."
    echo "###              Hosts              ###" >> ${DEBUG_LOG}

    if [ -e "$HOSTSFILE" ]
    then
	    cat "$HOSTSFILE" >> ${DEBUG_LOG}
	    echo >> ${DEBUG_LOG}
    else
	    echo "No hosts file found!" >> ${DEBUG_LOG}
	    printf ":::\tNo hosts file found!\n"
    fi
}

function portCheck {
  echo "############################################################" >> ${DEBUG_LOG}
	echo "########           Open Port Information           #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

    echo "::: Detecting local server port 80 and 53 processes."

    ${SUDO} lsof -i :80 >> ${DEBUG_LOG}
    ${SUDO} lsof -i :53 >> ${DEBUG_LOG}
    echo >> ${DEBUG_LOG}
}

function testResolver {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "############      Resolver Functions Check      ############" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}


	# Find a blocked url that has not been whitelisted.
    TESTURL="doubleclick.com"
	if [ -s "$WHITELISTMATCHES" ]; then
		while read -r line; do
			CUTURL=${line#*" "}
			if [ "$CUTURL" != "Pi-Hole.IsWorking.OK" ]; then
				while read -r line2; do
					CUTURL2=${line2#*" "}
					if [ "$CUTURL" != "$CUTURL2" ]; then
						TESTURL="$CUTURL"
						break 2
					fi
				done < "$WHITELISTMATCHES"
			fi
		done < "$GRAVITYFILE"
	fi

	echo "Resolution of $TESTURL from Pi-hole:" >> ${DEBUG_LOG}
	LOCALDIG=$(dig "$TESTURL" @127.0.0.1)
	if [[ $? = 0 ]]
	then
	    echo "$LOCALDIG" >> ${DEBUG_LOG}
	else
	    echo "Failed to resolve $TESTURL on Pi-hole" >> ${DEBUG_LOG}
	fi
	echo >> ${DEBUG_LOG}


	echo "Resolution of $TESTURL from 8.8.8.8:" >> ${DEBUG_LOG}
	REMOTEDIG=$(dig "$TESTURL" @8.8.8.8)
	if [[ $? = 0 ]]
	then
	    echo "$REMOTEDIG" >> ${DEBUG_LOG}
	else
	    echo "Failed to resolve $TESTURL on 8.8.8.8" >> ${DEBUG_LOG}
	fi
	echo >> ${DEBUG_LOG}

	echo "Pi-hole dnsmasq specific records lookups" >> ${DEBUG_LOG}
    echo "Cache Size:" >> ${DEBUG_LOG}
    dig +short chaos txt cachesize.bind >> ${DEBUG_LOG}
    echo "Insertions count:" >> ${DEBUG_LOG}
    dig +short chaos txt insertions.bind >> ${DEBUG_LOG}
    echo "Evictions count:" >> ${DEBUG_LOG}
    dig +short chaos txt evictions.bind >> ${DEBUG_LOG}
    echo "Misses count:" >> ${DEBUG_LOG}
    dig +short chaos txt misses.bind >> ${DEBUG_LOG}
    echo "Hits count:" >> ${DEBUG_LOG}
    dig +short chaos txt hits.bind >> ${DEBUG_LOG}
    echo "Auth count:" >> ${DEBUG_LOG}
    dig +short chaos txt auth.bind >> ${DEBUG_LOG}
    echo "Upstream Servers:" >> ${DEBUG_LOG}
    dig +short chaos txt servers.bind >> ${DEBUG_LOG}
    echo >> ${DEBUG_LOG}
}

function checkProcesses {
	echo "#######################################" >> ${DEBUG_LOG}
	echo "########### Processes Check ###########" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	echo ":::"
	echo "::: Logging status of lighttpd and dnsmasq..."
	PROCESSES=( lighttpd dnsmasq )
	for i in "${PROCESSES[@]}"
	do
		echo "" >> ${DEBUG_LOG}
		echo -n "$i" >> "$DEBUG_LOG"
		echo " processes status:" >> ${DEBUG_LOG}
		${SUDO} systemctl -l status "$i" >> "$DEBUG_LOG"
	done
	echo >> ${DEBUG_LOG}
}

function debugLighttpd {
	echo "::: Writing lighttpd to debug log..."
	echo "#######################################" >> ${DEBUG_LOG}
	echo "############ lighttpd.conf ############" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	if [ -e "$LIGHTTPDFILE" ]
	then
		while read -r line; do
			if [ ! -z "$line" ]; then
				[[ "$line" =~ ^#.*$ ]] && continue
				echo "$line" >> ${DEBUG_LOG}
			fi
		done < "$LIGHTTPDFILE"
		echo >> ${DEBUG_LOG}
	else
		echo "No lighttpd.conf file found!" >> ${DEBUG_LOG}
		printf ":::\tNo lighttpd.conf file found\n"
	fi
	
	if [ -e "$LIGHTTPDERRFILE" ]
	then
		echo "#######################################" >> ${DEBUG_LOG}
		echo "######### lighttpd error.log ##########" >> ${DEBUG_LOG}
		echo "#######################################" >> ${DEBUG_LOG}
		cat "$LIGHTTPDERRFILE" >> ${DEBUG_LOG}
	else
		echo "No lighttpd error.log file found!" >> ${DEBUG_LOG}
		printf ":::\tNo lighttpd error.log file found\n"
	fi
	echo >> ${DEBUG_LOG}
}

### END FUNCTIONS ###

version_check
distro_check
ip_check
hostnameCheck
portCheck
checkProcesses
testResolver
debugLighttpd

echo "::: Writing dnsmasq.conf to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "############### Dnsmasq ###############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$DNSMASQFILE" ]
then
	#cat $DNSMASQFILE >> $DEBUG_LOG
	while read -r line; do
		if [ ! -z "$line" ]; then
			[[ "$line" =~ ^#.*$ ]] && continue
			echo "$line" >> ${DEBUG_LOG}
        fi
	done < "$DNSMASQFILE"
	echo >> ${DEBUG_LOG}
else
	echo "No dnsmasq.conf file found!" >> ${DEBUG_LOG}
	printf ":::\tNo dnsmasq.conf file found!\n"
fi

echo "::: Writing 01-pihole.conf to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "########### 01-pihole.conf ############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$PIHOLECONFFILE" ]
then
	while read -r line; do
		if [ ! -z "$line" ]; then
			[[ "$line" =~ ^#.*$ ]] && continue
			echo "$line" >> ${DEBUG_LOG}
        fi
	done < "$PIHOLECONFFILE"
	echo >> ${DEBUG_LOG}
else
	echo "No 01-pihole.conf file found!" >> ${DEBUG_LOG}
	printf ":::\tNo 01-pihole.conf file found\n"
fi

echo "::: Writing size of gravity.list to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "############ gravity.list #############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$GRAVITYFILE" ]
then
	wc -l "$GRAVITYFILE" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
else
	echo "No gravity.list file found!" >> ${DEBUG_LOG}
	printf ":::\tNo gravity.list file found\n"
fi


### Pi-hole application specific logging ###
echo "::: Writing whitelist to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "############## Whitelist ##############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$WHITELISTFILE" ]
then
	cat "$WHITELISTFILE" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
else
	echo "No whitelist.txt file found!" >> ${DEBUG_LOG}
	printf ":::\tNo whitelist.txt file found!\n"
fi

echo "::: Writing blacklist to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "############## Blacklist ##############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$BLACKLISTFILE" ]
then
	cat "$BLACKLISTFILE" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
else
	echo "No blacklist.txt file found!" >> ${DEBUG_LOG}
	printf ":::\tNo blacklist.txt file found!\n"
fi

echo "::: Writing adlists.list to debug log..."
echo "#######################################" >> ${DEBUG_LOG}
echo "############ adlists.list #############" >> ${DEBUG_LOG}
echo "#######################################" >> ${DEBUG_LOG}
if [ -e "$ADLISTSFILE" ]
then
  while read -r line; do
    if [ ! -z "$line" ]; then
		  [[ "$line" =~ ^#.*$ ]] && continue
			echo "$line" >> ${DEBUG_LOG}
	fi
	done < "$ADLISTSFILE"
	echo >> ${DEBUG_LOG}
else
	echo "No adlists.list file found... using adlists.default!" >> ${DEBUG_LOG}
	printf ":::\tNo adlists.list file found... using adlists.default!\n"
fi


# Continuously append the pihole.log file to the pihole_debug.log file
function dumpPiHoleLog {
	trap '{ echo -e "\n::: Finishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo -e "::: Writing current Pi-hole traffic to debug log...\n:::\tTry loading any/all sites that you are having trouble with now... \n:::\t(Press ctrl+C to finish)"
	echo "#######################################" >> ${DEBUG_LOG}
	echo "############# pihole.log ##############" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	if [ -e "$PIHOLELOG" ]
	then
		while true; do
			tail -f "$PIHOLELOG" >> ${DEBUG_LOG}
			echo >> ${DEBUG_LOG}
		done
	else
		echo "No pihole.log file found!" >> ${DEBUG_LOG}
		printf ":::\tNo pihole.log file found!\n"
	fi
}

# Anything to be done after capturing of pihole.log terminates
function finalWork {
        echo "::: Finshed debugging!"
    echo "::: The debug log can be uploaded to Termbin.com for easier sharing."
        read -r -p "::: Would you like to upload the log? [y/N] " response
    case ${response} in
        [yY][eE][sS]|[yY])
            TERMBIN=$(cat /var/log/pihole_debug.log | nc termbin.com 9999)
            ;;
        *)
            echo "::: Log will NOT be uploaded to Termbin."
            ;;
    esac

        # Check if termbin.com is reachable. When it's not, point to local log instead
        if [ -n "$TERMBIN" ]
        then
                echo "::: Debug log can be found at : $TERMBIN"
        else
                echo "::: Debug log can be found at : /var/log/pihole_debug.log"
        fi
}

trap finalWork EXIT

### Method calls for additional logging ###
dumpPiHoleLog
