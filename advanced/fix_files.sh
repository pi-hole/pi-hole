#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2019 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Adjust file permissions for pihole-FTL
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Touch files to ensure they exist (create if non-existing, preserve if existing)
touch /var/log/pihole-FTL.log /var/log/pihole.log
touch /run/pihole-FTL.pid /run/pihole-FTL.port
touch /etc/pihole/dhcp.leases
mkdir -p /var/{run,log}/pihole
chown -f "$USER": /var/run/pihole /var/log/pihole
# Remove possible leftovers from previous pihole-FTL processes
rm -f /dev/shm/FTL-*
rm -f /var/run/pihole/FTL.sock
# Ensure that permissions are set so that pihole-FTL can edit all necessary files
chown -f "$USER": /run/pihole-FTL.pid /run/pihole-FTL.port
chown -f "$USER": /etc/pihole /etc/pihole/dhcp.leases
chown -f "$USER": /var/log/pihole-FTL.log /var/log/pihole.log
chmod 0644 /var/log/pihole-FTL.log /run/pihole-FTL.pid /run/pihole-FTL.port /var/log/pihole.log
