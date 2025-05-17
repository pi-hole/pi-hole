FROM alpine:3.21

ENV GITDIR=/etc/.pihole
ENV SCRIPTDIR=/opt/pihole
RUN sed -i 's/#\(.*\/community\)/\1/' /etc/apk/repositories
RUN apk add sudo curl coreutils abuild bash bind-tools git build-base

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $GITDIR/advanced/Scripts/COL_TABLE $SCRIPTDIR/
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ENV SKIP_INSTALL=true

#sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
