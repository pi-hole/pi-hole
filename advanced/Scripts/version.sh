#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Whitelists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.




normalOutput(){
piholeVersion=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
webVersion=$(cd /var/www/html/admin/ && git describe --tags --abbrev=0)

piholeVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
webVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')

echo "::: Pi-hole version is $piholeVersion (Latest version is $piholeVersionLatest)"
echo "::: Web-Admin version is $webVersion (Latest version is $webVersionLatest)"

}

for var in "$@"
do
  case "$var" in
    "-j" | "--json"  ) outputJSON;;
    "-h" | "--help"  ) displayHelp;;
    *                ) normalOutput;;
  esac
done