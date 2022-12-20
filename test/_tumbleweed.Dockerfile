FROM opensuse/tumbleweed

# installing `which` here because systemd would install `busybox-which`
# which conflicts with `which` installed later during basic-install.sh
RUN zypper install -y --no-recommends which git systemd-sysvinit dbus-1 libcap-progs


ENV GITDIR /etc/.pihole
ENV SCRIPTDIR /opt/pihole

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $SCRIPTDIR/
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ENV SKIP_INSTALL true
ENV OS_CHECK_DOMAIN_NAME dev-supportedos.pi-hole.net

ENV container docker
STOPSIGNAL SIGRTMIN+3

CMD ["/usr/sbin/init"]
