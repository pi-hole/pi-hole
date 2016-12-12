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
		"-h" | "--help"     ) helpFunc;;
	esac
done

shift

if [[ $# = 0 ]]; then
	helpFunc
fi

