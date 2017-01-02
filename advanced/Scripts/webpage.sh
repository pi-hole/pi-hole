#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Web interface settings
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

args=("$@")

helpFunc() {
	cat << EOM
::: Set admin options for the web interface of pihole
:::
::: Usage: pihole -a [options]
:::
::: Options:
:::  -p, password		Set web interface password, an empty input will remove any previously set password
:::  -c, celsius		Set Celsius temperature unit
:::  -f, fahrenheit		Set Fahrenheit temperature unit
:::  -k, kelvin			Set Kelvin temperature unit
:::  -h, --help			Show this help dialog
EOM
	exit 0
}

SetTemperatureUnit(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/TEMPERATUREUNIT/d' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "TEMPERATUREUNIT=${unit}" >> /etc/pihole/setupVars.conf

}

SetWebPassword(){

	if [ "${SUDO_USER}" == "www-data" ]; then
		echo "Security measure: user www-data is not allowed to change webUI password!"
		echo "Exiting"
		exit 1
	fi

	if [ "${SUDO_USER}" == "lighttpd" ]; then
		echo "Security measure: user lighttpd is not allowed to change webUI password!"
		echo "Exiting"
		exit 1
	fi

	# Remove password from file (create backup setupVars.conf.bak)
	sed -i.bak '/WEBPASSWORD/d' /etc/pihole/setupVars.conf
	# Set password only if there is one to be set
	if (( ${#args[2]} > 0 )) ; then
		# Compute password hash twice to avoid rainbow table vulnerability
		hash=$(echo -n ${args[2]} | sha256sum | sed 's/\s.*$//')
		hash=$(echo -n ${hash} | sha256sum | sed 's/\s.*$//')
		# Save hash to file
		echo "WEBPASSWORD=${hash}" >> /etc/pihole/setupVars.conf
		echo "New password set"
	else
		echo "WEBPASSWORD=" >> /etc/pihole/setupVars.conf
		echo "Password removed"
	fi

}

SetDNSServers(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/DNS_FQDN_REQUIRED/d;/DNS_BOGUS_PRIV/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "PIHOLE_DNS_1=${args[2]}" >> /etc/pihole/setupVars.conf
	if [[ "${args[3]}" != "none" ]]; then
		echo "PIHOLE_DNS_2=${args[3]}" >> /etc/pihole/setupVars.conf
	else
		echo "PIHOLE_DNS_2=" >> /etc/pihole/setupVars.conf
	fi

	# Replace within actual dnsmasq config file
	sed -i '/server=/d;' /etc/dnsmasq.d/01-pihole.conf
	echo "server=${args[2]}" >> /etc/dnsmasq.d/01-pihole.conf
	if [[ "${args[3]}" != "none" ]]; then
		echo "server=${args[3]}" >> /etc/dnsmasq.d/01-pihole.conf
	fi

	# Remove domain-needed entry
	sed -i '/domain-needed/d;' /etc/dnsmasq.d/01-pihole.conf

	# Readd it if required
	if [[ "${args[4]}" == "domain-needed" ]]; then
		echo "domain-needed" >> /etc/dnsmasq.d/01-pihole.conf
		echo "DNS_FQDN_REQUIRED=true" >> /etc/pihole/setupVars.conf
	else
		# Leave it deleted if not wanted
		echo "DNS_FQDN_REQUIRED=false" >> /etc/pihole/setupVars.conf
	fi

	# Remove bogus-priv entry
	sed -i '/bogus-priv/d;' /etc/dnsmasq.d/01-pihole.conf

	# Readd it if required
	if [[ "${args[5]}" == "bogus-priv" ]]; then
		echo "bogus-priv" >> /etc/dnsmasq.d/01-pihole.conf
		echo "DNS_BOGUS_PRIV=true" >> /etc/pihole/setupVars.conf
	else
		# Leave it deleted if not wanted
		echo "DNS_BOGUS_PRIV=false" >> /etc/pihole/setupVars.conf
	fi

	# Restart dnsmasq to load new configuration
	RestartDNS

}

SetExcludeDomains(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/API_EXCLUDE_DOMAINS/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "API_EXCLUDE_DOMAINS=${args[2]}" >> /etc/pihole/setupVars.conf
}

SetExcludeClients(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/API_EXCLUDE_CLIENTS/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "API_EXCLUDE_CLIENTS=${args[2]}" >> /etc/pihole/setupVars.conf
}

Reboot(){

	nohup bash -c "sleep 5; reboot" &> /dev/null </dev/null &

}

RestartDNS(){

	if [ -x "$(command -v systemctl)" ]; then
		systemctl restart dnsmasq &> /dev/null
	else
		service dnsmasq restart &> /dev/null
	fi

}

SetQueryLogOptions(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/API_QUERY_LOG_SHOW/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "API_QUERY_LOG_SHOW=${args[2]}" >> /etc/pihole/setupVars.conf
}

EnableDHCP(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/DHCP_/d;' /etc/pihole/setupVars.conf
	echo "DHCP_ACTIVE=true" >> /etc/pihole/setupVars.conf
	echo "DHCP_START=${args[2]}" >> /etc/pihole/setupVars.conf
	echo "DHCP_END=${args[3]}" >> /etc/pihole/setupVars.conf
	echo "DHCP_ROUTER=${args[4]}" >> /etc/pihole/setupVars.conf

	# Remove possible old setting from file
	sed -i '/dhcp-/d;/quiet-dhcp/d;' /etc/dnsmasq.d/01-pihole.conf

	# Get Pi-hole interface from setupVars.conf
	interface=$(grep 'PIHOLE_INTERFACE=' /etc/pihole/setupVars.conf | sed "s/.*=//")
	# Use eth0 as fallback interface
	if [ -z ${interface} ]; then
		interface="eth0"
	fi

	# Write settings to file
	echo "###############################################################################
#  DHCP SERVER CONFIG FILE AUTOMATICALLY POPULATED BY PI-HOLE WEB INTERFACE.  #
#            ANY CHANGES MADE TO THIS FILE WILL BE LOST ON CHANGE             #
###############################################################################

dhcp-authoritative

dhcp-range=${args[2]},${args[3]},infinite
dhcp-option=option:router,${args[4]}

dhcp-leasefile=/etc/pihole/dhcp.leases
quiet-dhcp
quiet-dhcp6

#enable-ra
dhcp-option=option6:dns-server,[::]
dhcp-range=::100,::1ff,constructor:${interface}
" > /etc/dnsmasq.d/02-pihole-dhcp.conf

	RestartDNS
}

DisableDHCP(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/DHCP_ACTIVE/d;' /etc/pihole/setupVars.conf
	echo "DHCP_ACTIVE=false" >> /etc/pihole/setupVars.conf

	# Remove possibly set setting from file
	sed -i '/dhcp-/d;/quiet-dhcp/d;' /etc/dnsmasq.d/01-pihole.conf

	# Remove settings file
	rm /etc/dnsmasq.d/02-pihole-dhcp.conf

	RestartDNS
}

SetWebUILayout(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/WEBUIBOXEDLAYOUT/d;' /etc/pihole/setupVars.conf
	echo "WEBUIBOXEDLAYOUT=${args[2]}" >> /etc/pihole/setupVars.conf

}

SetDNSDomainName(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/PIHOLE_DOMAIN/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "PIHOLE_DOMAIN=${args[2]}" >> /etc/pihole/setupVars.conf

	# Replace within actual dnsmasq config file
	sed -i '/domain=/d;' /etc/dnsmasq.d/01-pihole.conf
	echo "domain=${args[2]}" >> /etc/dnsmasq.d/01-pihole.conf

	# Restart dnsmasq to load new configuration
	RestartDNS

}

SetPrivacyMode(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/API_PRIVACY_MODE/d' /etc/pihole/setupVars.conf
	# Save setting to file
	if [[ "${args[2]}" == "true" ]] ; then
		echo "API_PRIVACY_MODE=true" >> /etc/pihole/setupVars.conf
	else
		echo "API_PRIVACY_MODE=false" >> /etc/pihole/setupVars.conf
	fi
}

ResolutionSettings() {

	typ=${args[2]}
	state=${args[3]}

	if [[ "${typ}" == "forward" ]]; then
		sed -i.bak '/API_GET_UPSTREAM_DNS_HOSTNAME/d;' /etc/pihole/setupVars.conf
		echo "API_GET_UPSTREAM_DNS_HOSTNAME=${state}" >> /etc/pihole/setupVars.conf
	elif [[ "${typ}" == "clients" ]]; then
		sed -i.bak '/API_GET_CLIENT_HOSTNAME/d;' /etc/pihole/setupVars.conf
		echo "API_GET_CLIENT_HOSTNAME=${state}" >> /etc/pihole/setupVars.conf
	fi
}

case "${args[1]}" in
	"-p" | "password"   ) SetWebPassword;;
	"-c" | "celsius"    ) unit="C"; SetTemperatureUnit;;
	"-f" | "fahrenheit" ) unit="F"; SetTemperatureUnit;;
	"-k" | "kelvin"     ) unit="K"; SetTemperatureUnit;;
	"setdns"            ) SetDNSServers;;
	"setexcludedomains" ) SetExcludeDomains;;
	"setexcludeclients" ) SetExcludeClients;;
	"reboot"            ) Reboot;;
	"restartdns"        ) RestartDNS;;
	"setquerylog"       ) SetQueryLogOptions;;
	"enabledhcp"        ) EnableDHCP;;
	"disabledhcp"       ) DisableDHCP;;
	"layout"            ) SetWebUILayout;;
	"-h" | "--help"     ) helpFunc;;
	"domainname"        ) SetDNSDomainName;;
	"privacymode"       ) SetPrivacyMode;;
	"resolve"           ) ResolutionSettings;;
	*                   ) helpFunc;;
esac

shift

if [[ $# = 0 ]]; then
	helpFunc
fi

