#!/usr/bin/env bash

mkdir /etc/pihole
echo release/v4.0 | sudo tee /etc/pihole/ftlbranch
git clone https://github.com/pi-hole/pi-hole.git /etc/.pihole
cd /etc/.pihole
git checkout release/v4.0
bash /etc/.pihole/automated\ install/basic-install.sh
pihole checkout web release/v4.0
