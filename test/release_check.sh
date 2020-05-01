#! /usr/bin/env bash
#apt install lighttpd -y

if type apt-get &> /dev/null; then
  sudo apt update
  sudo apt -y install git
elif type yum &> /dev/null; then
  echo "yum install git"
  sudo yum install git
fi

sudo git clone https://github.com/pi-hole/AdminLTE.git /var/www/html/admin
pushd "$_"
sudo git checkout release/v5.0
popd

sudo git clone https://github.com/pi-hole/pi-hole.git /etc/.pihole
pushd "$_"
sudo git checkout release/v5.0
popd

sudo mkdir -pv /etc/pihole
echo "release/v5.0" |sudo tee /etc/pihole/ftlbranch

/etc/.pihole/automated\ install/basic-install.sh