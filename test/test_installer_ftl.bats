#!/usr/bin/env bats
# Installer tests for FTL architecture detection and binary installation

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-mock/stub'
load 'bats_helper.bash'

TICK="[✓]"
INFO="[i]"

FTL_BRANCH="development"

# ---------------------------------------------------------------------------
# Installer FTL architecture detection — one @test per arch
# ---------------------------------------------------------------------------

_test_ftl_arch() {
    local arch="$1" detected_string="$2" supported="$3"

    # Resolve the sh binary path the installer will interrogate so we stub
    # exactly the call that will be made, rather than all possible paths.
    local sh_path
    sh_path="$(command -v sh)"

    stub uname "-m : echo '${arch}'"
    stub readelf "-A ${sh_path} : echo 'Tag_CPU_arch: ${arch}'"
    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch

    run bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "

    if [[ "${supported}" == "true" ]]; then
        assert_output --partial "${INFO} FTL Checks..."
        assert_output --partial "${TICK} Detected ${detected_string} architecture"

        if [[ "${output}" != *"Downloading and Installing FTL"* && "${output}" != *"Local binary up-to-date. No need to download!"* ]]; then
            echo "Expected either download or up-to-date path, got:" >&2
            echo "${output}" >&2
            false
        fi
    else
        assert_output --partial "Not able to detect architecture (unknown: ${detected_string})"
    fi

    unstub uname   2>/dev/null || true
    unstub readelf 2>/dev/null || true
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

# ---------------------------------------------------------------------------
# FTLcheckUpdate — errors while asking the GitHub API for the latest release
# ---------------------------------------------------------------------------

_run_ftl_check_update_on_master() {
    # The GitHub API is only asked on the master branch, and only when
    # pihole-FTL is already installed, so put a placeholder binary on the PATH
    echo "master" > /etc/pihole/ftlbranch
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/sh\n' >"${BATS_TEST_TMPDIR}/bin/pihole-FTL"
    chmod +x "${BATS_TEST_TMPDIR}/bin/pihole-FTL"

    run bash -c "
        PATH=\"${BATS_TEST_TMPDIR}/bin:\${PATH}\"
        source /opt/pihole/basic-install.sh
        FTLcheckUpdate pihole-FTL-amd64 || exit \$?
    "
}

@test "FTLcheckUpdate reports when the GitHub API rate limit is exceeded" {
    stub curl "-s https://api.github.com/repos/pi-hole/FTL/releases/latest : echo '{\"message\":\"API rate limit exceeded for 192.0.2.1.\"}'"

    _run_ftl_check_update_on_master

    assert_failure 5
    assert_output --partial "GitHub API rate limit exceeded, please try again later"
    unstub curl
}

@test "FTLcheckUpdate reports other failures to get the latest release" {
    stub curl "-s https://api.github.com/repos/pi-hole/FTL/releases/latest : exit 6"

    _run_ftl_check_update_on_master

    assert_failure 3
    assert_output --partial "Failed to retrieve latest FTL release metadata"
    refute_output --partial "rate limit"
    unstub curl
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
