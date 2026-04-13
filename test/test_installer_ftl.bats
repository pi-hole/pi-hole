#!/usr/bin/env bats
# Installer tests for FTL architecture detection and binary installation

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
TICK="[✓]"
INFO="[i]"

FTL_BRANCH="development"

# ---------------------------------------------------------------------------
# Installer FTL architecture detection for the active runtime platform
# ---------------------------------------------------------------------------

_run_installer_ftl_detect() {
    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch

    run bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "
}

_expected_arch_message_for_platform() {
    local platform="${TEST_PLATFORM:-linux/amd64}"
    case "$platform" in
        linux/amd64) echo "Detected x86_64 architecture" ;;
        linux/386) echo "Detected 32bit (i686) architecture" ;;
        linux/arm/v6) echo "Detected ARMv6 architecture" ;;
        linux/arm/v7) echo "Detected ARMv7 (or newer) architecture" ;;
        linux/arm64|linux/arm64/v8) echo "Detected AArch64 (64 Bit ARM) architecture" ;;
        linux/riscv64) echo "Detected riscv64 architecture" ;;
        *) echo "" ;;
    esac
}

_expected_arch_label_for_platform() {
    local platform="${TEST_PLATFORM:-linux/amd64}"
    case "$platform" in
        linux/amd64) echo "x86_64" ;;
        linux/386) echo "32bit (i686)" ;;
        linux/arm/v6) echo "ARMv6" ;;
        linux/arm/v7) echo "ARMv7 (or newer)" ;;
        linux/arm64|linux/arm64/v8) echo "AArch64 (64 Bit ARM)" ;;
        linux/riscv64) echo "riscv64" ;;
        *) echo "unknown" ;;
    esac
}

@test "installer detects $(_expected_arch_label_for_platform) architecture for TEST_PLATFORM" {
    local expected
    expected="$(_expected_arch_message_for_platform)"

    if [[ -z "$expected" ]]; then
        skip "No expected installer architecture mapping for TEST_PLATFORM='${TEST_PLATFORM:-unset}'"
    fi

    # Under QEMU emulation the host kernel's uname -m is reported inside the container
    # rather than the architecture of the emulated platform. When that mismatch is
    # detected, the installer will select the host architecture's binary (which is still
    # functional), but asserting the expected arch label would be wrong. Skip instead.
    local machine
    machine=$(uname -m)
    case "${TEST_PLATFORM:-linux/amd64}" in
        linux/arm/v6|linux/arm/v7)
            # ARM 32-bit containers on a non-ARM32 host (e.g. arm64 CI runner) report
            # aarch64 via uname -m; the installer selects the arm64 binary instead.
            if [[ "${machine}" != "arm"* ]]; then
                skip "uname -m reports '${machine}', not ARM32 — QEMU on a non-ARM32 host; skipping arch-detection assertion"
            fi
            ;;
        linux/386)
            # On non-dpkg systems (e.g. Alpine) there is no dpkg --print-architecture to
            # distinguish a 32-bit container from a native x86_64 host under QEMU.
            if [[ "${machine}" == "x86_64" ]] && ! command -v dpkg &>/dev/null; then
                skip "uname -m reports 'x86_64' and dpkg is absent — cannot distinguish i686 from x86_64 under QEMU; skipping arch-detection assertion"
            fi
            ;;
    esac

    _run_installer_ftl_detect

    assert_output --partial "${INFO} FTL Checks..."
    assert_output --partial "${TICK} ${expected}"

    if [[ "$output" != *"Downloading and Installing FTL"* && "$output" != *"Local binary up-to-date. No need to download!"* ]]; then
        echo "Expected either download or up-to-date path, got:" >&2
        echo "$output" >&2
        false
    fi
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
