FROM docker.io/fedora:35
RUN dnf --setopt=install_weak_deps=False install -y git systemd

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

CMD ["/usr/sbin/init"]
