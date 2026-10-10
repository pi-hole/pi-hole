#!/usr/bin/env bats
# Tests for piholeLogFlush.sh

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'libs/bats-mock/stub'
load 'bats_helper.bash'

# ---------------------------------------------------------------------------

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

@test "piholeLogFlush once reports failure when logrotate fails" {
    stub logrotate "--force /etc/logrotate.d/pihole : exit 1"

    run bash /opt/pihole/piholeLogFlush.sh once quiet
    assert_failure
    assert_output --partial "Failed to rotate logs"

    unstub logrotate
}
