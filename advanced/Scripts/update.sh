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

# Variables
webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
piholeFilesDir="/etc/.pihole"

    if [ ! -d "/etc/.pihole" ]; then #This is unlikely
        echo "::: Critical Error: Pi-Hole repo missing from system!"
        echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
        exit 1;
    fi
    if [ ! -d "/var/www/html/admin" ]; then #This is unlikely
        echo "::: Critical Error: Pi-Hole repo missing from system!"
        echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
        exit 1;
    fi

    echo "::: Checking for updates..."
    piholeVersion=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
    piholeVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')

    webVersion=$(cd /var/www/html/admin/ && git describe --tags --abbrev=0)
    webVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')

    echo "::: Pi-hole version is $piholeVersion (Latest version is $piholeVersionLatest)"
    echo "::: Web Admin version is $webVersion (Latest version is $webVersionLatest)"
    echo ":::"

    if [[ ${piholeVersion} == ${piholeVersionLatest} ]] ; then
        echo "::: Pi-hole Base files are already up to date! Version: ${piholeVersionLatest}"
        echo "::: No need to update!"
        echo ":::"

        if [[ ${webVersion} == ${webVersionLatest} ]] ; then
            echo "::: Web Admin files are already up to date!  Version: ${webVersionLatest}"
            echo "::: No need to update!"
            echo ":::"
        else
            echo "::: An Update is available for the Web Admin!"
            echo ":::"
            echo "::: Fetching latest changes from GitHub..."
            # Update Git files for Core
            getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl}
            echo ":::"
            echo "::: Pi-hole Web Admin has been updated to ${webVersionLatest}"
            echo "::: See https://changes.pi-hole.net for details"
        fi
    else
        echo -n "::: An update is available for "
        if [[ ${webVersion} == ${webVersionLatest} ]] ; then
            echo " Pi-Hole!"
        else
            echo " Pi-Hole base files and the Web Admin. Both will be updated!"
        fi

        echo "::: Fetching latest changes from GitHub..."
        # Update Git files for Core
        getGitFiles ${piholeFilesDir} ${piholeGitUrl}
        /etc/.pihole/automated\ install/basic-install.sh --unattended

        echo ":::"
        echo "::: Pi-hole has been updated to version ${piholeVersionLatest}"
        if [[ ${webVersion} != ${webVersionLatest} ]] ; then
            echo "::: Web Admin has been updated to version ${webVersionLatest}"
        fi
        echo ":::"
        echo "::: See https://changes.pi-hole.net for details"
    fi

    exit 0