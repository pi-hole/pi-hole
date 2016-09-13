FROM debian:jessie

ENV GITDIR /etc/.pihole
ENV SCRIPTDIR /opt/pihole

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $SCRIPTDIR/ && \
    rmdir /usr/local/bin && ln -s $SCRIPTDIR/ /usr/local/bin

RUN true && \
    sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
    chmod +x $SCRIPTDIR/*
