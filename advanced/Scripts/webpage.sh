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
:::  -c, celsius		Set Celcius temperature unit
:::  -f, fahrenheit		Set Fahrenheit temperature unit
:::  -h, --help			Show this help dialog
EOM
	exit 0
}

SetTemperatureUnit(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/TEMPERATUREUNIT/d' /etc/pihole/setupVars.conf
	# Save setting to file
	if [[ $unit == "F" ]] ; then
		echo "TEMPERATUREUNIT=F" >> /etc/pihole/setupVars.conf
	else
		echo "TEMPERATUREUNIT=C" >> /etc/pihole/setupVars.conf
	fi

}

SetWebPassword(){

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
		echo "Password removed"
	fi

}

SetDNSServers(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;' /etc/pihole/setupVars.conf
	# Save setting to file
	echo "PIHOLE_DNS_1=${args[2]}" >> /etc/pihole/setupVars.conf
	echo "PIHOLE_DNS_2=${args[3]}" >> /etc/pihole/setupVars.conf

	# Replace within actual dnsmasq config file
	sed -i '/server=/d;' /etc/dnsmasq.d/01-pihole.conf
	echo "server=${args[2]}" >> /etc/dnsmasq.d/01-pihole.conf
	echo "server=${args[3]}" >> /etc/dnsmasq.d/01-pihole.conf

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

	reboot

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

	# Remove setting from file
	sed -i '/dhcp-/d;' /etc/dnsmasq.d/01-pihole.conf
	# Save setting to file
	echo "dhcp-range=${args[2]},${args[3]},infinite" >> /etc/dnsmasq.d/01-pihole.conf
	echo "dhcp-option=option:router,${args[4]}" >> /etc/dnsmasq.d/01-pihole.conf
	# Changes the behaviour from strict RFC compliance so that DHCP requests on unknown leases from unknown hosts are not ignored. This allows new hosts to get a lease without a tedious timeout under all circumstances. It also allows dnsmasq to rebuild its lease database without each client needing to reacquire a lease, if the database is lost.
	echo "dhcp-authoritative" >> /etc/dnsmasq.d/01-pihole.conf
	# Use the specified file to store DHCP lease information
	echo "dhcp-leasefile=/etc/pihole/dhcp.leases" >> /etc/dnsmasq.d/01-pihole.conf

	RestartDNS
}

DisableDHCP(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/DHCP_ACTIVE/d;' /etc/pihole/setupVars.conf
	echo "DHCP_ACTIVE=false" >> /etc/pihole/setupVars.conf

	# Remove setting from file
	sed -i '/dhcp-/d;' /etc/dnsmasq.d/01-pihole.conf

	RestartDNS
}

for var in "$@"; do
	case "${var}" in
		"-p" | "password"   ) SetWebPassword;;
		"-c" | "celsius"    ) unit="C"; SetTemperatureUnit;;
		"-f" | "fahrenheit" ) unit="F"; SetTemperatureUnit;;
		"setdns"            ) SetDNSServers;;
		"setexcludedomains" ) SetExcludeDomains;;
		"setexcludeclients" ) SetExcludeClients;;
		"reboot"            ) Reboot;;
		"restartdns"        ) RestartDNS;;
		"setquerylog"       ) SetQueryLogOptions;;
		"enabledhcp"        ) EnableDHCP;;
		"disabledhcp"       ) DisableDHCP;;
		"-h" | "--help"     ) helpFunc;;
	esac
done

shift

if [[ $# = 0 ]]; then
	helpFunc
fi

