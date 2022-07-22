FROM alpine:latest

ENV GITDIR /etc/.pihole
ENV SCRIPTDIR /opt/pihole
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR
ENV SKIP_INSTALL true
ENV OS_CHECK_DOMAIN_NAME dev-supportedos.pi-hole.net

COPY . $GITDIR

RUN apk --no-cache add bash busybox-initscripts coreutils curl git python3 sudo; \
    echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel; \
    python3 -m ensurepip; \
    ln -sf pip3 /usr/bin/pip; \
    ln -sf python3 /usr/bin/python; \
    mkdir -p $GITDIR $SCRIPTDIR /etc/pihole; \
    cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $SCRIPTDIR/; \
    true && \
    chmod +x $SCRIPTDIR/*

#sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
