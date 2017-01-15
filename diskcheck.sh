#!/usr/bin/env bash

rows=$(tput lines)
columns=$(tput cols)

r=$(( rows / 2 ))
c=$(( columns / 2 ))

verifyFreeDiskSpace() {
    # 25MB may be a realistic minimum (20MB install + 5MB one day of logs.)
    # requiredFreeBytes=25600

    # 90GB will probably force a fail for testing.
    requiredFreeBytes=90000000

    existingFreeBytes=`df -lkP / | awk '{print $4}' | tail -1`

    if [[ $existingFreeBytes -lt $requiredFreeBytes ]]; then
        whiptail --msgbox --backtitle "Insufficient Disk Space" --title "Insufficient Disk Space" "\nYour system appears to be low on disk space. pi-hole recomends a minimum of $requiredFreeBytes Bytes.\nYou only have $existingFreeBytes Free.\n\nIf this is a new install you may need to expand your disk.\n\nTry running:\n    'sudo raspi-config'\nChoose the 'expand file system option'\n\nAfter rebooting, run this installation again.\n\ncurl -L install.pi-hole.net | bash\n" $r $c
        exit 1
    # else and echo are only here for testing.
    else
        echo "Installing"
    fi
}

# This function call should go after the welcomeDialogs function.
verifyFreeDiskSpace
# echo is only here to show when the install would continue.
echo "Still running"
