#!/usr/bin/env bash

mkdir /etc/pihole
echo release/v4.0 | sudo tee /etc/pihole/ftlbranch
curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/release/v4.0/automated%20install/basic-install.sh | bash
pihole checkout web release/v4.0
