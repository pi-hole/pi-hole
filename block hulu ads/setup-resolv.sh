# !/bin/bash
sudo mv /etc/resolv.conf /etc/resolv.conf.orig
sudo curl -s "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/dnsmasq.conf" > /etc/resolv.conf
sudo service dnsmasq start
