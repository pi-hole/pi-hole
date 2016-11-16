#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Whitelists and blacklists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

args=("$@")

helpFunc() {
	cat << EOM
::: Set options for the web interface of pihole
:::
::: Usage: pihole -web [options]
:::
::: Options:
:::  -p, password		Set web interface password
:::  -c, celsius		Set Celcius temperature unit
:::  -f, fahrenheit		Set Fahrenheit temperature unit
:::  -h, --help			Show this help dialog
EOM
	exit 1
}

SetTemperatureUnit(){

	# Remove setting from file (create backup setupVars.conf.bak)
	sed -i.bak '/temperatureunit/d' /etc/pihole/setupVars.conf
	# Save setting to file
	if [[ $unit == "F" ]] ; then
		echo "temperatureunit=F" >> /etc/pihole/setupVars.conf
	else
		echo "temperatureunit=C" >> /etc/pihole/setupVars.conf
	fi

}

SetWebPassword(){

	# Remove password from file (create backup setupVars.conf.bak)
	sed -i.bak '/webpassword/d' /etc/pihole/setupVars.conf
	# Compute password hash
	hash=$(echo -n ${args[2]} | sha256sum | sed 's/\s.*$//')
	# Save hash to file
	echo "webpassword=${hash}" >> /etc/pihole/setupVars.conf

}

for var in "$@"; do
	case "${var}" in
		"-p" | "password"   ) SetWebPassword;;
		"-c" | "celsius"    ) unit="C"; SetTemperatureUnit;;
		"-f" | "fahrenheit" ) unit="F"; SetTemperatureUnit;;
		"-h" | "--help"     ) helpFunc;;
	esac
done

shift

if [[ $# = 0 ]]; then
	helpFunc
fi

