#!/usr/bin/env sh

# Source utils.sh for getFTLPIDFile()
PI_HOLE_SCRIPT_DIR='/opt/pihole'
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck disable=SC1090
. "${utilsfile}"

# Get file paths
FTL_PID_FILE="$(getFTLPIDFile)"

# Touch files to ensure they exist (create if non-existing, preserve if existing)
# shellcheck disable=SC2174
mkdir -pm 0755 /run/pihole /var/log/pihole
[ -f "${FTL_PID_FILE}" ] || install -D -m 644 -o pihole -g pihole /dev/null "${FTL_PID_FILE}"
[ -f /var/log/pihole/FTL.log ] || install -m 644 -o pihole -g pihole /dev/null /var/log/pihole/FTL.log
[ -f /var/log/pihole/pihole.log ] || install -m 640 -o pihole -g pihole /dev/null /var/log/pihole/pihole.log
[ -f /etc/pihole/dhcp.leases ] || install -m 644 -o pihole -g pihole /dev/null /etc/pihole/dhcp.leases
# Ensure that permissions are set so that pihole-FTL can edit all necessary files
chown -R pihole:pihole /run/pihole /etc/pihole /var/log/pihole
chmod -R 0640 /var/log/pihole
chmod -R 0660 /etc/pihole /run/pihole

# Backward compatibility for user-scripts that still expect log files in /var/log instead of /var/log/pihole
# Should be removed with Pi-hole v6.0
if [ ! -f /var/log/pihole.log ]; then
    ln -sf /var/log/pihole/pihole.log /var/log/pihole.log
    chown -h pihole:pihole /var/log/pihole.log
fi
if [ ! -f /var/log/pihole-FTL.log ]; then
    ln -sf /var/log/pihole/FTL.log /var/log/pihole-FTL.log
    chown -h pihole:pihole /var/log/pihole-FTL.log
fi
