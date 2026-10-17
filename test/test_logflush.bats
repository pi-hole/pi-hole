#!/usr/bin/env bats
# Tests for piholeLogFlush.sh

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'libs/bats-mock/stub'
load 'bats_helper.bash'

# ---------------------------------------------------------------------------

setup() {
    mkdir -p "${BATS_TEST_TMPDIR}/shim"

    cat > "${BATS_TEST_TMPDIR}/shim/pihole-FTL" <<EOF
#!/bin/sh
case "\$3" in
    files.log.dnsmasq)   printf '%s\n' "${BATS_TEST_TMPDIR}/pihole.log" ;;
    files.log.ftl)       printf '%s\n' "${BATS_TEST_TMPDIR}/FTL.log" ;;
    files.log.webserver) printf '%s\n' "${BATS_TEST_TMPDIR}/webserver.log" ;;
    dns.port)            printf '53\n' ;;
esac
EOF

    cat > "${BATS_TEST_TMPDIR}/shim/dig" <<'EOF'
#!/bin/sh
printf '"http://localhost:80/api/"\n'
EOF

    cat > "${BATS_TEST_TMPDIR}/shim/curl" <<'EOF'
#!/bin/sh
case "$*" in
    */auth*) printf '{}>>200' ;;
    *)       printf '{}200' ;;
esac
EOF

    cat > "${BATS_TEST_TMPDIR}/shim/sudo" <<'EOF'
#!/bin/sh
shift 2
exec "$@"
EOF

    chmod +x \
        "${BATS_TEST_TMPDIR}/shim/pihole-FTL" \
        "${BATS_TEST_TMPDIR}/shim/dig" \
        "${BATS_TEST_TMPDIR}/shim/curl" \
        "${BATS_TEST_TMPDIR}/shim/sudo"

    export PATH="${BATS_TEST_TMPDIR}/shim:${PATH}"

    printf 'query log content\n' > "${BATS_TEST_TMPDIR}/pihole.log"
    printf 'ftl log content\n' > "${BATS_TEST_TMPDIR}/FTL.log"
    printf 'web log content\n' > "${BATS_TEST_TMPDIR}/webserver.log"
}

@test "piholeLogFlush once quiet outputs no text and exits 0" {
    stub logrotate "--force /etc/logrotate.d/pihole : exit 0"

    run bash /opt/pihole/piholeLogFlush.sh once quiet
    assert_success
    assert_output ""

    unstub logrotate
}

@test "piholeLogFlush quiet once (reversed argument order) outputs no text" {
    stub logrotate "--force /etc/logrotate.d/pihole : exit 0"

    run bash /opt/pihole/piholeLogFlush.sh quiet once
    assert_success
    assert_output ""

    unstub logrotate
}

@test "piholeLogFlush once without quiet shows running and rotated messages" {
    stub logrotate "--force /etc/logrotate.d/pihole : exit 0"

    run bash /opt/pihole/piholeLogFlush.sh once
    assert_success
    assert_output --partial "Running logrotate"
    assert_output --partial "Rotated logs"

    unstub logrotate
}

@test "piholeLogFlush quiet on manual flush outputs no text and truncates logs" {
    run bash /opt/pihole/piholeLogFlush.sh quiet
    assert_success
    assert_output ""

    for logfile in pihole.log FTL.log webserver.log; do
        run cat "${BATS_TEST_TMPDIR}/${logfile}"
        assert_output " "
    done
}

@test "piholeLogFlush manual flush without quiet shows flushing and flushed messages" {
    run bash /opt/pihole/piholeLogFlush.sh
    assert_success
    assert_output --partial "Flushing ${BATS_TEST_TMPDIR}/pihole.log"
    assert_output --partial "Flushed ${BATS_TEST_TMPDIR}/pihole.log"
    assert_output --partial "Flushed ${BATS_TEST_TMPDIR}/FTL.log"
    assert_output --partial "Flushed ${BATS_TEST_TMPDIR}/webserver.log"
    assert_output --partial "Flushing the queries of the last 24 hours"
    assert_output --partial "Flushed the queries of the last 24 hours"
}
