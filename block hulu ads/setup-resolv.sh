# !/bin/bash
# DNS config file
# Run as a local script since modifying it will disconnect the Internet connection
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo mv /etc/dnsmasq.conf.pihole /etc/dnsmasq.conf
sudo service dnsmasq start
