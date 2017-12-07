#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes Pi-hole's log file
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

colfile="/opt/pihole/COL_TABLE"
source ${colfile}

if [[ "$@" != *"quiet"* ]]; then
  echo -ne "  ${INFO} Flushing /var/log/pihole.log ..."
fi
if [[ "$@" == *"once"* ]]; then
  # Nightly logrotation
  if command -v /usr/sbin/logrotate >/dev/null; then
    # Logrotate once
    /usr/sbin/logrotate --force /etc/pihole/logrotate
  else
    # Copy pihole.log over to pihole.log.1
    # and empty out pihole.log
    # Note that moving the file is not an option, as
    # dnsmasq would happily continue writing into the
    # moved file (it will have the same file handler)
    cp /var/log/pihole.log /var/log/pihole.log.1
    echo " " > /var/log/pihole.log
  fi
else
  # Manual flushing
  if command -v /usr/sbin/logrotate >/dev/null; then
    # Logrotate twice to move all data out of sight of FTL
    /usr/sbin/logrotate --force /etc/pihole/logrotate; sleep 3
    /usr/sbin/logrotate --force /etc/pihole/logrotate
  else
    # Flush both pihole.log and pihole.log.1 (if existing)
    echo " " > /var/log/pihole.log
    if [ -f /var/log/pihole.log.1 ]; then
      echo " " > /var/log/pihole.log.1
    fi
  fi
fi

if [[ "$@" != *"quiet"* ]]; then
  echo -e "${OVER}  ${TICK} Flushed /var/log/pihole.log"
fi
