#!/usr/bin/env sh

# Source utils.sh for getFTLConfigValue()
PI_HOLE_CONFIG_DIR="/etc/pihole"
PI_HOLE_SCRIPT_DIR='/opt/pihole'
# shellcheck source="./advanced/Scripts/utils.sh"
. "${PI_HOLE_SCRIPT_DIR}/utils.sh"

# Get file paths
FTL_PID_FILE="$(getFTLConfigValue files.pid)"

# Ensure that permissions are set so that pihole-FTL can edit all necessary files
mkdir -p /var/log/pihole
chown -R pihole:pihole "$PI_HOLE_CONFIG_DIR" /var/log/pihole/

# allow all users read version file (and use pihole -v)
chmod 0644 "${PI_HOLE_CONFIG_DIR}/versions"

# allow pihole to access subdirs in /etc/pihole (sets execution bit on dirs)
find "$PI_HOLE_CONFIG_DIR" /var/log/pihole/ -type d -exec chmod 0755 {} +
# Set all files (except TLS-related ones) to u+rw g+r
find "$PI_HOLE_CONFIG_DIR" /var/log/pihole/ -type f ! \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0640 {} +
# Set TLS-related files to a more restrictive u+rw *only* (they may contain private keys)
find "$PI_HOLE_CONFIG_DIR" -type f \( -name '*.pem' -o -name '*.crt' \) -exec chmod 0600 {} +

# Logrotate config file need to be owned by root
chown root:root "${PI_HOLE_CONFIG_DIR}/logrotate"

# Touch files to ensure they exist (create if non-existing, preserve if existing)
[ -f "${FTL_PID_FILE}" ] || install -D -m 644 -o pihole -g pihole /dev/null "${FTL_PID_FILE}"
[ -f /var/log/pihole/FTL.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/FTL.log
[ -f /var/log/pihole/pihole.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/pihole.log
[ -f /var/log/pihole/webserver.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/webserver.log
[ -f "${PI_HOLE_CONFIG_DIR}/dhcp.leases" ] || install -m 644 -o pihole -g pihole /dev/null "${PI_HOLE_CONFIG_DIR}/dhcp.leases"
