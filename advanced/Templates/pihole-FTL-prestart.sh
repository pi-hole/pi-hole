#!/usr/bin/env sh

# Ensure that permissions are set so that pihole-FTL can edit all necessary files
mkdir -p /var/log/pihole
chown -R pihole:pihole /etc/pihole/ /var/log/pihole/

# Set permissions on everything below /etc/pihole and /var/log/pihole:
#   directories:           rwxr-xr-x (so pihole can access subdirs)
#   files:                 rw-r----- (u+rw g+r)
#   TLS .pem/.crt files:   rw------- (u+rw *only*, they may contain private keys)
#
# The chown above made the pihole user the owner of both trees, so pihole can
# rearrange them freely. find only builds a list of paths and chmod acts on
# them afterwards, so if root ran these, pihole could swap an entry for a symlink
# in between and root's chmod would follow it, changing the permissions of a file
# pihole has no business touching (e.g. /etc/shadow). So drop privileges and let
# the pihole user do it: it owns everything below these directories, and a
# symlink pointing anywhere else only results in a permission error.
# A failure here is deliberately non-fatal so it can never prevent FTL starting.
su -s /bin/sh pihole -c '
    find /etc/pihole/ /var/log/pihole/ -type d -exec chmod 0755 {} +
    find /etc/pihole/ /var/log/pihole/ -type f ! \( -name "*.pem" -o -name "*.crt" \) -exec chmod 0640 {} +
    find /etc/pihole/ -type f \( -name "*.pem" -o -name "*.crt" \) -exec chmod 0600 {} +
' || true

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
