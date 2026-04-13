#!/usr/bin/env bats
# FTL architecture detection and binary installation tests

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'helpers/mocks'

TICK="[✓]"
INFO="[i]"

FTL_BRANCH="development"

setup() {
    rm -f /usr/local/bin/uname /usr/local/bin/readelf /var/log/uname /var/log/readelf
}

teardown() {
    rm -f /usr/local/bin/uname /usr/local/bin/readelf /var/log/uname /var/log/readelf
}

# ---------------------------------------------------------------------------
# FTL architecture detection — one @test per arch (replaces parametrize)
# ---------------------------------------------------------------------------

_test_ftl_arch() {
    local arch="$1" detected_string="$2" supported="$3"

    mock_command uname "-m" "$arch" "0"
    mock_command_2 readelf \
        "-A /bin/sh"      "Tag_CPU_arch: ${arch}" "0" \
        "-A /usr/bin/sh"  "Tag_CPU_arch: ${arch}" "0" \
        "-A /usr/sbin/sh" "Tag_CPU_arch: ${arch}" "0"
    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch

    run bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "

    if [[ "$supported" == "true" ]]; then
        assert_output --partial "${INFO} FTL Checks..."
        assert_output --partial "${TICK} Detected ${detected_string} architecture"

        if [[ "$output" != *"Downloading and Installing FTL"* && "$output" != *"Local binary up-to-date. No need to download!"* ]]; then
            echo "Expected either download or up-to-date path, got:" >&2
            echo "$output" >&2
            false
        fi
    else
        assert_output --partial "Not able to detect architecture (unknown: ${detected_string})"
    fi
}

@test "FTL detects aarch64 architecture" {
    _test_ftl_arch "aarch64" "AArch64 (64 Bit ARM)" "true"
}

@test "FTL detects ARMv6 architecture" {
    _test_ftl_arch "armv6" "ARMv6" "true"
}

@test "FTL detects ARMv7l architecture" {
    _test_ftl_arch "armv7l" "ARMv7 (or newer)" "true"
}

@test "FTL detects ARMv7 architecture" {
    _test_ftl_arch "armv7" "ARMv7 (or newer)" "true"
}

@test "FTL detects ARMv8a architecture" {
    _test_ftl_arch "armv8a" "ARMv7 (or newer)" "true"
}

@test "FTL detects x86_64 architecture" {
    _test_ftl_arch "x86_64" "x86_64" "true"
}

@test "FTL detects riscv64 architecture" {
    _test_ftl_arch "riscv64" "riscv64" "true"
}

@test "FTL reports unsupported architecture" {
    _test_ftl_arch "mips" "mips" "false"
}

@test "FTL development binary is installed and responsive" {
    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch
    bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "
    run bash -c '
        VERSION=$(pihole-FTL version)
        echo "${VERSION:0:1}"
    '
    assert_output --partial "v"
}
