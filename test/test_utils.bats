#!/usr/bin/env bats
# Tests for utils.sh

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

_reset_utils_test_state() {
    rm -f ./testoutput
}

setup() {
    _reset_utils_test_state
}

teardown() {
    _reset_utils_test_state
}

# ---------------------------------------------------------------------------

@test "addOrEditKeyValPair adds and replaces key-value pairs correctly" {
    bash -c "
        source /opt/pihole/utils.sh
        addOrEditKeyValPair './testoutput' 'KEY_ONE' 'value1'
        addOrEditKeyValPair './testoutput' 'KEY_TWO' 'value2'
        addOrEditKeyValPair './testoutput' 'KEY_ONE' 'value3'
        addOrEditKeyValPair './testoutput' 'KEY_FOUR' 'value4'
    "
    run bash -c "cat ./testoutput"
    assert_output "KEY_ONE=value3
KEY_TWO=value2
KEY_FOUR=value4"
}

@test "getFTLPID returns -1 when FTL is not running" {
    run bash -c "
        source /opt/pihole/utils.sh
        getFTLPID
    "
    assert_output "-1"
}

@test "setFTLConfigValue and getFTLConfigValue round-trip" {
    # FTL must be installed for this test
    bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        echo 'development' > /etc/pihole/ftlbranch
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "
    run bash -c "
        source /opt/pihole/utils.sh
        setFTLConfigValue 'dns.upstreams' '[\"9.9.9.9\"]' > /dev/null
        getFTLConfigValue 'dns.upstreams'
    "
    assert_output --partial "[ 9.9.9.9 ]"
}
