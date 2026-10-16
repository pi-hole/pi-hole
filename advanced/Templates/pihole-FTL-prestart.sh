#!/usr/bin/env sh

# Ensure that permissions are set so that pihole-FTL can edit all necessary files
mkdir -p /var/log/pihole
chown -R pihole:pihole /etc/pihole/ /var/log/pihole/

# allow pihole to access subdirs in /etc/pihole (sets execution bit on dirs)
find /etc/pihole/ /var/log/pihole/ -type d -exec chmod 0755 {} +
# Set all files (except TLS-related ones) to u+rw g+r
find /etc/pihole/ /var/log/pihole/ -type f ! \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0640 {} +
# Set TLS-related files to a more restrictive u+rw *only* (they may contain private keys)
find /etc/pihole/ -type f \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0600 {} +

# allow all users read version file (and use pihole -v)
# This has to come after the find commands above, which would reset it to 0640
touch /etc/pihole/versions
chmod 0644 /etc/pihole/versions

# Touch files to ensure they exist (create if non-existing, preserve if existing)
# Hardcoded PID path — see GHSA-6w8x-p785-6pm4
[ -f /run/pihole-FTL.pid ] || install -D -m 644 -o pihole -g pihole /dev/null /run/pihole-FTL.pid
[ -f /etc/pihole/dhcp.leases ] || install -m 644 -o pihole -g pihole /dev/null /etc/pihole/dhcp.leases
