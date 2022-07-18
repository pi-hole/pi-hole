FROM alpine:latest

ENV GITDIR /etc/.pihole
ENV SCRIPTDIR /opt/pihole
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR
ENV SKIP_INSTALL true
ENV OS_CHECK_DOMAIN_NAME dev-supportedos.pi-hole.net

COPY . $GITDIR

RUN apk --no-cache add git; \
    mkdir -p $GITDIR $SCRIPTDIR /etc/pihole; \
    cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $SCRIPTDIR/; \
    true && \
    chmod +x $SCRIPTDIR/*

#sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
