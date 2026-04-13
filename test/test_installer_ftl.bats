#!/usr/bin/env bats
# Installer tests for FTL architecture detection and binary installation

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'helpers/mocks'

TICK="[✓]"
INFO="[i]"

FTL_BRANCH="development"

_reset_ftl_test_state() {
    rm -f /usr/local/bin/uname /usr/local/bin/readelf /var/log/uname /var/log/readelf
}

setup() {
    _reset_ftl_test_state
}

teardown() {
    _reset_ftl_test_state
}

# ---------------------------------------------------------------------------
# Installer FTL architecture detection — one @test per arch
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

@test "installer detects aarch64 architecture for FTL" {
    _test_ftl_arch "aarch64" "AArch64 (64 Bit ARM)" "true"
}

@test "installer detects ARMv6 architecture for FTL" {
    _test_ftl_arch "armv6" "ARMv6" "true"
}

@test "installer detects ARMv7l architecture for FTL" {
    _test_ftl_arch "armv7l" "ARMv7 (or newer)" "true"
}

@test "installer detects ARMv7 architecture for FTL" {
    _test_ftl_arch "armv7" "ARMv7 (or newer)" "true"
}

@test "installer detects ARMv8a architecture for FTL" {
    _test_ftl_arch "armv8a" "ARMv7 (or newer)" "true"
}

@test "installer detects x86_64 architecture for FTL" {
    _test_ftl_arch "x86_64" "x86_64" "true"
}

@test "installer detects riscv64 architecture for FTL" {
    _test_ftl_arch "riscv64" "riscv64" "true"
}

@test "installer reports unsupported architecture for FTL" {
    _test_ftl_arch "mips" "mips" "false"
}

@test "installer provides a responsive FTL development binary" {
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
