FROM quay.io/centos/centos:stream9
# Disable SELinux
RUN echo "SELINUX=disabled" > /etc/selinux/config
RUN yum install -y --allowerasing curl git initscripts

ENV GITDIR=/etc/.pihole
ENV SCRIPTDIR=/opt/pihole

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $GITDIR/advanced/Scripts/COL_TABLE $SCRIPTDIR/
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ENV SKIP_INSTALL=true

#sed '/# Start the installer/Q' /opt/pihole/basic-install.sh > /opt/pihole/stub_basic-install.sh && \
