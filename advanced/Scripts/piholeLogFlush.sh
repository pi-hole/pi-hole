#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes /var/log/pihole.log
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



echo -n "::: Flushing /var/log/pihole.log ..."
# Test if logrotate is available on this system
if command -v /usr/sbin/logrotate &> /dev/null; then
  /usr/sbin/logrotate --force /etc/pihole/logrotate
else
  echo " " > /var/log/pihole.log
fi
echo "... done!"
