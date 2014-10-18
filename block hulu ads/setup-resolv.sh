# !/bin/bash
sudo mv /etc/resolv.conf /etc/resolv.conf.orig
sudo mv /etc/resolv.conf.pihole /etc/resolv.conf
sudo service dnsmasq start
