# !/bin/bash
sudo mv /etc/resolv.conf /etc/resolv.conf.orig
sudo curl -o /etc/resolv.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/dnsmasq.conf"
sudo service dnsmasq start
