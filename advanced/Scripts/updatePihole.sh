#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Checks if Pi-hole needs updating and then
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Taken from http://stackoverflow.com/questions/3258243/check-if-pull-needed-in-git

# Move into the git directory
cd /etc/.pihole/

LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u})
BASE=$(git merge-base @ @{u})

if [[ $LOCAL = $REMOTE ]]; then
  echo "Up-to-date"
elif [[ $LOCAL = $BASE ]]; then
  echo "Updating Pi-hole..."
  git pull
  /opt/pihole/updatePiholeSecondary.sh
elif [[ $REMOTE = $BASE ]]; then
  : # Need to push, so do nothing
else
  : # Diverged, so do nothing
fi
