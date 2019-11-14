#!/bin/sh

# To use this:
# docker run -v $(pwd):/pihole -it alpine /bin/sh
# /pihole/alpine-install-wrapper.sh # from within the container
#

cd "$(dirname "$0")" || exit

if [ ! -d /etc/.pihole/ ]; then
  apk add bash
  bash ./basic-install.sh
fi

if pihole-FTL 2>&1 | grep -q "Operation not permitted"; then
  if [ ! -f FTL/pihole-FTL ]; then
    apk update
    apk add git alpine-sdk linux-headers gmp-dev nettle-dev openssh-client sqlite bash bind-tools libcap shadow
    git clone https://github.com/pi-hole/FTL
    cd FTL || exit
    git checkout development
    make
    # ./pihole-FTL -v && ldd ./pihole-FTL
    cd "$(dirname "$0")" || exit
  fi
  cp FTL/pihole-FTL /usr/bin/pihole-FTL
fi

mkdir -p /run/openrc/
touch /run/openrc/softlevel
openrc
service lighttpd start 2>/dev/null

echo | pihole -a -p # Delete Admin password

if ! pgrep pihole-FTL >/dev/null; then
  /usr/bin/pihole-FTL
fi

pihole status # enables it

# lbu commit -d # to persist changes across restarts for Alpine
