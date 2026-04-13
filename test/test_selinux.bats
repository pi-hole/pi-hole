#!/usr/bin/env bats
# Tests for SELinux handling in basic-install.sh.
# Only runs on rhel family (CentOS/Fedora) — selected by run.sh.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'helpers/mocks'

TICK="[✓]"
CROSS="[✗]"

_reset_selinux_test_state() {
    rm -f /usr/local/bin/getenforce /var/log/getenforce
}

setup() {
    _reset_selinux_test_state
}

teardown() {
    _reset_selinux_test_state
}

_mock_selinux_config() {
    local state="$1"   # enforcing, permissive, or disabled
    local capitalized
    capitalized=$(echo "${state}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    mock_command getenforce "*" "$capitalized" "0"
    mkdir -p /etc/selinux
    echo "SELINUX=${state}" > /etc/selinux/config
}

@test "SELinux enforcing: installer exits with error" {
    _mock_selinux_config "enforcing"
    run bash -c "
        source /opt/pihole/basic-install.sh
        checkSelinux
    "
    assert_output --partial "${CROSS} Current SELinux: enforcing"
    assert_output --partial "SELinux Enforcing detected, exiting installer"
    assert_failure
}

@test "SELinux permissive: installer continues" {
    _mock_selinux_config "permissive"
    run bash -c "
        source /opt/pihole/basic-install.sh
        checkSelinux
    "
    assert_output --partial "${TICK} Current SELinux: permissive"
    assert_success
}

@test "SELinux disabled: installer continues" {
    _mock_selinux_config "disabled"
    run bash -c "
        source /opt/pihole/basic-install.sh
        checkSelinux
    "
    assert_output --partial "${TICK} Current SELinux: disabled"
    assert_success
}
