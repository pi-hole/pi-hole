#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Flushes /var/log/pihole.log
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

echo -n "::: Flushing /var/log/pihole.log ..."
# Test if logrotate is available on this system
if command -v /usr/sbin/logrotate &> /dev/null; then
  /usr/sbin/logrotate --force /etc/pihole/logrotate
else
  echo " " > /var/log/pihole.log
fi
echo "... done!"
