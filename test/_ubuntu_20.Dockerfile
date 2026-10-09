FROM buildpack-deps:focal-scm

ENV GITDIR=/etc/.pihole
ENV SCRIPTDIR=/opt/pihole

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/pihole
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/pihole $GITDIR/automated\ install/*.sh $GITDIR/advanced/Scripts/COL_TABLE $SCRIPTDIR/
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ARG BATS_CORE_VER
ARG BATS_SUPPORT_VER
ARG BATS_ASSERT_VER
ARG BATS_MOCK_VER
ARG BATS_FILE_VER
RUN git clone --depth=1 --single-branch --branch "${BATS_CORE_VER}"    https://github.com/bats-core/bats-core    $GITDIR/test/libs/bats && \
    git clone --depth=1 --single-branch --branch "${BATS_SUPPORT_VER}" https://github.com/bats-core/bats-support $GITDIR/test/libs/bats-support && \
    git clone --depth=1 --single-branch --branch "${BATS_ASSERT_VER}"  https://github.com/bats-core/bats-assert  $GITDIR/test/libs/bats-assert && \
    git clone --depth=1 --single-branch --branch "${BATS_MOCK_VER}"    https://github.com/jasonkarns/bats-mock   $GITDIR/test/libs/bats-mock && \
    git clone --depth=1 --single-branch --branch "${BATS_FILE_VER}"    https://github.com/bats-core/bats-file    $GITDIR/test/libs/bats-file

ENV SKIP_INSTALL=true

