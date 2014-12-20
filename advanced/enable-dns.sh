# !/bin/bash
# Download the ad list
sudo /usr/local/bin/gravity.sh

# Enable DNS and start blocking ads
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo mv /etc/dnsmasq.conf.pihole /etc/dnsmasq.conf
sudo service dnsmasq start
