#!/bin/bash
/bin/touch /var/log/pihole-FTL.log /run/pihole-FTL.pid /run/pihole-FTL.port /var/log/pihole.log
/bin/mkdir -p /var/run/pihole /var/log/pihole
/bin/chown pihole:pihole /var/run/pihole /var/log/pihole
if [ -e "/var/run/pihole/FTL.sock" ]; then
  /bin/rm /var/run/pihole/FTL.sock
fi
/bin/chown pihole:pihole /var/log/pihole-FTL.log /run/pihole-FTL.pid /run/pihole-FTL.port /etc/pihole /etc/pihole/dhcp.leases /var/log/pihole.log
/bin/chmod 0644 /var/log/pihole-FTL.log /run/pihole-FTL.pid /run/pihole-FTL.port /var/log/pihole.log
/bin/echo "nameserver 127.0.0.1" | /sbin/resolvconf -a lo.piholeFTL
