#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Sets permissions to pihole files and directories
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

source /usr/local/include/pihole/piholeInclude

rerun_root "$0" "$@"

chown --recursive root:pihole /etc/pihole
chmod --recursive ug=rwX,o=rX /etc/pihole
