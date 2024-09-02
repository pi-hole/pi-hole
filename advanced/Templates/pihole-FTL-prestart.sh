#!/usr/bin/env sh

# Source utils.sh for getFTLConfigValue()
PI_HOLE_SCRIPT_DIR='/opt/pihole'
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck disable=SC1090
. "${utilsfile}"

# Get file paths
FTL_PID_FILE="$(getFTLConfigValue files.pid)"

# Ensure that permissions are set so that pihole-FTL can edit all necessary files
# shellcheck disable=SC2174
mkdir -pm 0640 /var/log/pihole
chown -R pihole:pihole /etc/pihole /var/log/pihole
chmod -R 0640 /var/log/pihole
chmod -R 0660 /etc/pihole

# Logrotate config file need to be owned by root and must not be writable by group and others
chown root:root /etc/pihole/logrotate
chmod 0644 /etc/pihole/logrotate

# allow all users to enter the directories
chmod 0755 /etc/pihole /var/log/pihole

# allow pihole to access subdirs in /etc/pihole (sets execution bit on dirs)
# credits https://stackoverflow.com/a/11512211
find /etc/pihole -type d -exec chmod 0755 {} \;

# Touch files to ensure they exist (create if non-existing, preserve if existing)
[ -f "${FTL_PID_FILE}" ] || install -D -m 644 -o pihole -g pihole /dev/null "${FTL_PID_FILE}"
[ -f /var/log/pihole/FTL.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/FTL.log
[ -f /var/log/pihole/pihole.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/pihole.log
[ -f /etc/pihole/dhcp.leases ] || install -m 644 -o pihole -g pihole /dev/null /etc/pihole/dhcp.leases
