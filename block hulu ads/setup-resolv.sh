# !/bin/bash
# Resolver file
sudo mv /etc/resolv.conf /etc/resolv.conf.orig
sudo mv /etc/resolv.conf.pihole /etc/resolv.conf
# DNS config file
sudo mv /etc/dnsmasq.conf /etc/rdnsmasq.conf.orig
sudo mv /etc/dnsmasq.conf.pihole /etc/dnsmasq.conf
sudo service dnsmasq start
