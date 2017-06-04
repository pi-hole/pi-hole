#!/bin/bash
FTL_communicate() {
  # Open connection to FTL
  exec 3<>"/dev/tcp/localhost/4711"

  # Test if connection is open
  if { "true" >&3; } 2> /dev/null; then
    # Send command to FTL
    echo -e ">$1" >&3

    # Read input
    read -r -t 1 LINE <&3
    until [[ ! $? ]] || [[ "$LINE" == *"EOM"* ]]; do
       echo "$LINE" >&1
       read -r -t 1 LINE <&3
    done

    # Close connection
    exec 3>&-
    exec 3<&-
  fi
}

FTL_get_version() {
  FTL_communicate "version"
}

FTL_get_stats() {
  FTL_communicate "stats"
}

FTL_get_top_clients() {
  FTL_communicate "top-clients"
}

FTL_get_top_domains() {
  FTL_communicate "top-domains"
}

FTL_prepare_files() {
  ts=$(dnsmasq_pre)
cat <<EOT >> /var/log/pihole.log
${ts} query[AAAA] raspberrypi from 127.0.0.1
${ts} /etc/pihole/local.list raspberrypi is fda2:2001:5647:0:ba27:ebff:fe37:4205
${ts} query[A] checkip.dyndns.org from 127.0.0.1
${ts} forwarded checkip.dyndns.org to 2001:1608:10:25::9249:d69b
${ts} forwarded checkip.dyndns.org to 2001:1608:10:25::1c04:b12f
${ts} forwarded checkip.dyndns.org to 2620:0:ccd::2
${ts} forwarded checkip.dyndns.org to 2620:0:ccc::2
${ts} reply checkip.dyndns.org is <CNAME>
${ts} reply checkip.dyndns.com is 216.146.38.70
${ts} reply checkip.dyndns.com is 216.146.43.71
${ts} reply checkip.dyndns.com is 91.198.22.70
${ts} reply checkip.dyndns.com is 216.146.43.70
${ts} query[A] pi.hole from 10.8.0.2
${ts} /etc/pihole/local.list pi.hole is 192.168.2.10
${ts} query[A] play.google.com from 192.168.2.208
${ts} forwarded play.google.com to 2001:1608:10:25::9249:d69b
${ts} forwarded play.google.com to 2001:1608:10:25::1c04:b12f
${ts} forwarded play.google.com to 2620:0:ccd::2
${ts} forwarded play.google.com to 2620:0:ccc::2
${ts} reply play.google.com is <CNAME>
${ts} reply play.l.google.com is 216.58.208.110
${ts} reply play.l.google.com is 216.58.208.110
${ts} reply play.l.google.com is 216.58.208.110
${ts} reply play.google.com is <CNAME>
${ts} query[AAAA] play.google.com from 192.168.2.208
${ts} forwarded play.google.com to 2620:0:ccd::2
${ts} reply play.l.google.com is 2a00:1450:4017:802::200e
EOT
}

dnsmasq_pre() {
  echo -n $(date +"%b %e %H:%M:%S")
  echo -n "dnsmasq[123]:"
}
