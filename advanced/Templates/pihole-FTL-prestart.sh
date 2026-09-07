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

# Ensure the version and DHCP lease files exist and are readable by all local
# users (so e.g. `pihole -v` works). This has to come after the find commands
# above, which would reset the version file to 0640. /etc/pihole is owned by the unprivileged
# "pihole" user, so creating or chmod-ing these as root would follow a symlink
# that a compromised pihole user could plant in their place
# (GHSA-xch2-4qxw-g5vj). Let the pihole user do it instead: a symlink pointed at
# a root-owned file then only yields EPERM rather than clobbering the target.
# shellcheck disable=SC2016 # ${f} is expanded by the pihole shell, not this one
su -s /bin/sh -c '
    for f in /etc/pihole/versions /etc/pihole/dhcp.leases; do
        if [ -L "${f}" ] || [ ! -f "${f}" ]; then
            rm -f "${f}"
            : > "${f}"
        fi
        chmod 0644 "${f}" 2>/dev/null || true
    done
' pihole || true

# Touch files to ensure they exist (create if non-existing, preserve if existing)
# Hardcoded PID path — see GHSA-6w8x-p785-6pm4
[ -f /run/pihole-FTL.pid ] || install -D -m 644 -o pihole -g pihole /dev/null /run/pihole-FTL.pid
