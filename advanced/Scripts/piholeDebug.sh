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
if [[ $EUID -eq 0 ]]; then
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
function versionCheck {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "##########           Installed Versions           ##########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

	echo "::: Detecting Pi-hole installed versions."
	TMP=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
	echo "Pi-hole Version: $TMP" >> ${DEBUG_LOG}

	echo "::: Writing Pi-hole installed version to logfile."
	TMP=$(cd /var/www/html/admin && git describe --tags --abbrev=0)
	echo "WebUI Version: $TMP" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
}

function distroCheck {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "########          Installed OS Distribution        #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

	echo "::: Checking installed OS Distribution release."
	TMP=$(cat /etc/*release || echo "Failed to find release")

	echo "::: Writing OS Distribution release to logfile."
	echo "$TMP" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
}

function ipCheck {
	echo "############################################################" >> ${DEBUG_LOG}
	echo "########           IP Address Information          #########" >> ${DEBUG_LOG}
	echo "############################################################" >> ${DEBUG_LOG}

    echo "::: Writing local IPs to logfile"
    IPADDR=$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')
    echo "$IPADDR" >> ${DEBUG_LOG}

    IP6ADDR=$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')
    if [ -n "$IP6ADDR" ]
    then
    echo "$IP6ADDR" >> ${DEBUG_LOG}
    fi
    echo >> ${DEBUG_LOG}

    echo "::: Locating default gateway and checking connectivity"
    GATEWAY=$(ip r | grep default | cut -d ' ' -f 3)
    GATEWAY_CHECK=$(ping -q -w 1 -c 1 "${GATEWAY}" > /dev/null && echo ok || echo error)
    echo "Gateway check at ${GATEWAY}:" >> ${DEBUG_LOG}
    echo "$GATEWAY_CHECK" >> ${DEBUG_LOG}

    GATEWAY6=$(ip -6 r | grep default | cut -d ' ' -f 3)
    if [ -n "$GATEWAY6" ]
    then
    GATEWAY6_CHECK=$(ping6 -q -w 1 -c 1 "${GATEWAY6}" > /dev/null && echo ok || echo error)
    echo "IPv6 Gateway check at ${GATEWAY6}:" >> ${DEBUG_LOG}
    echo "$GATEWAY6_CHECK" >> ${DEBUG_LOG}
    fi
    echo >> ${DEBUG_LOG}
}

function hostnameCheck {
    # Write the hostname output to compare against entries in /etc/hosts, which is logged next
    echo "Hostname of this pihole is: " >> ${DEBUG_LOG}
    hostname >> ${DEBUG_LOG}

    echo "::: Writing hosts file to debug log..."
    echo "#######################################" >> ${DEBUG_LOG}
    echo "################ Hosts ################" >> ${DEBUG_LOG}
    echo "#######################################" >> ${DEBUG_LOG}
    if [ -e "$HOSTSFILE" ]
    then
	    cat "$HOSTSFILE" >> ${DEBUG_LOG}
	    echo >> ${DEBUG_LOG}
    else
	    echo "No hosts file found!" >> ${DEBUG_LOG}
	    printf ":::\tNo hosts file found!\n"
    fi
}

function compareWhitelist {
	if [ ! -f "$WHITELISTMATCHES" ]; then
		${SUDO} touch ${WHITELISTMATCHES}
		${SUDO} chmod 644 ${WHITELISTMATCHES}
		${SUDO} chown "$USER":root ${WHITELISTMATCHES}
	else
		truncate -s 0 ${WHITELISTMATCHES}
	fi

	echo "#######################################" >> ${DEBUG_LOG}
	echo "######## Whitelist Comparison #########" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	while read -r line; do
		TMP=$(grep -w ".* $line$" "$GRAVITYFILE")
		if [ ! -z "$TMP" ]; then
			echo "$TMP" >> ${DEBUG_LOG}
			echo "$TMP"	>> ${WHITELISTMATCHES}
		fi
	done < "$WHITELISTFILE"
	echo >> ${DEBUG_LOG}
}

function compareBlacklist {
	echo "#######################################" >> ${DEBUG_LOG}
	echo "######## Blacklist Comparison #########" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	while read -r line; do
		if [ ! -z "$line" ]; then
			grep -w ".* $line$" "$GRAVITYFILE" >> ${DEBUG_LOG}
		fi
	done < "$BLACKLISTFILE"
	echo >> ${DEBUG_LOG}
}

function testNslookup {
	TESTURL="doubleclick.com"
	echo "#######################################" >> ${DEBUG_LOG}
	echo "############ NSLookup Test ############" >> ${DEBUG_LOG}
	echo "#######################################" >> ${DEBUG_LOG}
	# Find a blocked url that has not been whitelisted.
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

	echo "NSLOOKUP of $TESTURL from PiHole:" >> ${DEBUG_LOG}
	nslookup "$TESTURL" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
	echo "NSLOOKUP of $TESTURL from 8.8.8.8:" >> ${DEBUG_LOG}
	nslookup "$TESTURL" 8.8.8.8 >> ${DEBUG_LOG}
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


versionCheck
distroCheck
ipCheck
hostnameCheck
compareWhitelist
compareBlacklist
testNslookup
checkProcesses
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


### PiHole application specific logging ###
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
	cat "$ADLISTSFILE" >> ${DEBUG_LOG}
	echo >> ${DEBUG_LOG}
else
	echo "No adlists.list file found... using adlists.default!" >> ${DEBUG_LOG}
	printf ":::\tNo adlists.list file found... using adlists.default!\n"
fi


# Continuously append the pihole.log file to the pihole_debug.log file
function dumpPiHoleLog {
	trap '{ echo -e "\n::: Finishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo -e "::: Writing current pi-hole traffic to debug log...\n:::\tTry loading any/all sites that you are having trouble with now... \n:::\t(Press ctrl+C to finish)"
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
