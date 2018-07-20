#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Automatically configures the Pi to use the 2.8 LCD screen to display stats on it (also works over ssh)
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



############ FUNCTIONS ###########

# Borrowed from adafruit-pitft-helper < borrowed from raspi-config
# https://github.com/adafruit/Adafruit-PiTFT-Helper/blob/master/adafruit-pitft-helper#L324-L334
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

# Borrowed from adafruit-pitft-helper:
# https://github.com/adafruit/Adafruit-PiTFT-Helper/blob/master/adafruit-pitft-helper#L274-L285
autoLoginPiToConsole() {
    if [ -e /etc/init.d/lightdm ]; then
        if [ ${SYSTEMD} -eq 1 ]; then
            systemctl set-default multi-user.target
            ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
        else
            update-rc.d lightdm disable 2
            sed /etc/inittab -i -e "s/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/1:2345:respawn:\/bin\/login -f pi tty1 <\/dev\/tty1 >\/dev\/tty1 2>&1/"
        fi
    fi
}

######### SCRIPT ###########
# Set pi to log in automatically
getInitSys
autoLoginPiToConsole

# Set chronomter to run automatically when pi logs in
echo /usr/local/bin/chronometer.sh >> /home/pi/.bashrc
# OR
#$SUDO echo /usr/local/bin/chronometer.sh >> /etc/profile

# Set up the LCD screen based on Adafruits instuctions:
# https://learn.adafruit.com/adafruit-pitft-28-inch-resistive-touchscreen-display-raspberry-pi/easy-install
curl -SLs https://apt.adafruit.com/add-pin | bash
apt-get -y install raspberrypi-bootloader
apt-get -y install adafruit-pitft-helper
adafruit-pitft-helper -t 28r

# Download the cmdline.txt file that prevents the screen from going blank after a period of time
mv /boot/cmdline.txt /boot/cmdline.orig
curl -o /boot/cmdline.txt https://raw.githubusercontent.com/pi-hole/pi-hole/master/advanced/cmdline.txt

# Back up the original file and download the new one
mv /etc/default/console-setup /etc/default/console-setup.orig
curl -o /etc/default/console-setup https://raw.githubusercontent.com/pi-hole/pi-hole/master/advanced/console-setup

# Instantly apply the font change to the LCD screen
setupcon

reboot

# Start showing the stats on the screen by running the command on another tty:
# http://unix.stackexchange.com/questions/170063/start-a-process-on-a-different-tty
#setsid sh -c 'exec /usr/local/bin/chronometer.sh <> /dev/tty1 >&0 2>&1'
