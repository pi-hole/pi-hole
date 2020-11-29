FROM buildpack-deps:bionic-scm

ENV GITDIR /etc/.pihole
ENV SCRIPTDIR /opt/pihole

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $SCRIPTDIR/
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ENV PH_TEST true

#sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
