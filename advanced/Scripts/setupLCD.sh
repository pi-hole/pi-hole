#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
#
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# pi-hole.net/donate

getInitSys() {
  if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
    SYSTEMD=1
  elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
    SYSTEMD=0
  else
    echo "Unrecognised init system"
    return 1
  fi
}

autoLoginPiToConsole() {
  if [ -e /etc/init.d/lightdm ]; then
    if [ $SYSTEMD -eq 1 ]; then
      $SUDO systemctl set-default multi-user.target
      $SUDO ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
    else
      $SUDO update-rc.d lightdm disable 2
      $SUDO sed /etc/inittab -i -e "s/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/1:2345:respawn:\/bin\/login -f pi tty1 <\/dev\/tty1 >\/dev\/tty1 2>&1/"
      fi
  fi
}


getInitSys
# Set pi to log in automatically
autoLoginPiToConsole

# Set chronomter to run automatically when pi logs in
$SUDO echo /usr/local/bin/chronometer.sh >> /home/pi/.bashrc

# Back up the original file and download the new one
$SUDO mv /etc/default/console-setup /etc/default/console-setup.orig
$SUDO curl -o /etc/default/console-setup https://raw.githubusercontent.com/pi-hole/pi-hole/master/advanced/console-setup

# Instantly apply the font change to the LCD screen
$SUDO setupcon

$SUDO /usr/local/bin/chronometer.sh
