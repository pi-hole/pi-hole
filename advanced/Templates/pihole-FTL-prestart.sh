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
# users (so that e.g. `pihole -v` works). This has to come after the find
# commands above, which would reset the version file to 0640.
#
# /etc/pihole is owned by the unprivileged "pihole" user, who could plant a
# symlink at either path pointing at a file only root can write. If root then
# touched/chmod-ed the path it would follow the symlink and modify the target
# (GHSA-xch2-4qxw-g5vj). So drop privileges and let the pihole user do it:
#   touch - creates the file if it is missing, otherwise leaves it as is
#   chmod - sets the mode to rw-r--r--
# Should the path be a symlink to something pihole has no rights to, both
# commands simply fail with a permission error and the target is left untouched.
# A failure here is deliberately non-fatal so it can never prevent FTL starting.
# su is needed to change user; both files are handled in a single call.
su -s /bin/sh pihole -c 'touch /etc/pihole/versions /etc/pihole/dhcp.leases && chmod 0644 /etc/pihole/versions /etc/pihole/dhcp.leases' || true

# Touch files to ensure they exist (create if non-existing, preserve if existing)
# Hardcoded PID path — see GHSA-6w8x-p785-6pm4
[ -f /run/pihole-FTL.pid ] || install -D -m 644 -o pihole -g pihole /dev/null /run/pihole-FTL.pid
