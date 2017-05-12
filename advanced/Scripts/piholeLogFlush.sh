#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes Pi-hole's log file
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

echo -n "::: Flushing /var/log/pihole.log ..."
# Test if logrotate is available on this system
if command -v /usr/sbin/logrotate >/dev/null; then
  # Flush twice to move all data out of sight of FTL
  /usr/sbin/logrotate --force /etc/pihole/logrotate; sleep 3
  /usr/sbin/logrotate --force /etc/pihole/logrotate
else
  # Flush both pihole.log and pihole.log.1 (if existing)
  echo " " > /var/log/pihole.log
  if [ -f /var/log/pihole.log.1 ]; then
    echo " " > /var/log/pihole.log.1
  fi
fi
echo "... done!"
