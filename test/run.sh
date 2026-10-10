#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# CLI arguments (optional)
# ---------------------------------------------------------------------------

usage() {
    echo "Usage:"
    echo "  DISTRO=<name> bash test/run.sh"
    echo "  bash test/run.sh --distro <name>"
    echo ""
    echo "Options:"
    echo "  -d, --distro <name>   Distro to test (e.g., debian_12)"
    echo "  -h, --help            Show this help"
}

list_distros() {
    find . -maxdepth 1 -name '_*.Dockerfile' | sed 's|^\./||;s/^_//;s/\.Dockerfile$//' | sort
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--distro)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: --distro requires a value"
                usage
                exit 1
            fi
            DISTRO="$1"
            ;;
        -h|--help)
            usage
            echo ""
            echo "Available distros:"
            list_distros
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Distro selection
# ---------------------------------------------------------------------------

if [[ -z "${DISTRO:-}" ]]; then
    echo "Error: DISTRO is required."
    echo "Example: DISTRO=debian_12 bash test/run.sh"
    echo "or:      bash test/run.sh --distro debian_12"
    echo ""
    echo "Available distros:"
    list_distros
    exit 1
fi

DOCKERFILE="_${DISTRO}.Dockerfile"
if [[ ! -f "${DOCKERFILE}" ]]; then
    echo "Error: Unknown distro '${DISTRO}'. Available distros:"
    list_distros | sed 's/^/  /'
    exit 1
fi

# Determine distro family to select which test files to run.
# rhel: CentOS/Fedora — includes SELinux tests
# alpine: Alpine Linux
# debian: Debian/Ubuntu (default)
distro_family() {
    case "$1" in
        centos_* | fedora_*) echo "rhel" ;;
        alpine_*) echo "alpine" ;;
        *) echo "debian" ;;
    esac
}
DISTRO_FAMILY=$(distro_family "${DISTRO}")

# ---------------------------------------------------------------------------
# Suite definitions
#
# Suite 1 — mock/function tests: run together in one container.  Each test
#   cleans up its own state via setup()/teardown(); no full install occurs.
#
# Suite 2 — fresh install: runs alone in its own container so the installer
#   can mutate the filesystem freely without needing any teardown.
# ---------------------------------------------------------------------------

SUITE_1=(
    test_automated_install.bats
    test_installer_ftl.bats
    test_network.bats
    test_utils.bats
    test_gravity.bats
    test_logflush.bats
)
[[ "${DISTRO_FAMILY}" == "rhel" ]] && SUITE_1+=(test_selinux.bats)

SUITE_2=(test_fresh_install.bats)

# ---------------------------------------------------------------------------
# BATS library versions — single source of truth, passed to Docker as build
# args so the Dockerfiles themselves stay version-agnostic.  Override any of
# these by setting the corresponding environment variable before calling this
# script, e.g. BATS_CORE_VER=v1.14.0 bash test/run.sh --distro debian_12
# ---------------------------------------------------------------------------

BATS_CORE_VER="${BATS_CORE_VER:-v1.13.0}"
BATS_SUPPORT_VER="${BATS_SUPPORT_VER:-v0.3.0}"
BATS_ASSERT_VER="${BATS_ASSERT_VER:-v2.2.4}"
BATS_MOCK_VER="${BATS_MOCK_VER:-v1.2.5}"
BATS_FILE_VER="${BATS_FILE_VER:-v0.4.0}"

# ---------------------------------------------------------------------------
# Build the test image (once, shared by both suites)
# ---------------------------------------------------------------------------

IMAGE_TAG="pihole_test:${DISTRO}"

docker buildx build \
    --load \
    --progress plain \
    --build-arg "BATS_CORE_VER=${BATS_CORE_VER}" \
    --build-arg "BATS_SUPPORT_VER=${BATS_SUPPORT_VER}" \
    --build-arg "BATS_ASSERT_VER=${BATS_ASSERT_VER}" \
    --build-arg "BATS_MOCK_VER=${BATS_MOCK_VER}" \
    --build-arg "BATS_FILE_VER=${BATS_FILE_VER}" \
    -f "${DOCKERFILE}" \
    -t "${IMAGE_TAG}" \
    ../

# ---------------------------------------------------------------------------
# Configure BATS output
# ---------------------------------------------------------------------------

BATS_FLAGS=();

# Use pretty output when stdout is a terminal; TAP format for CI
if [[ -t 1 ]]; then
    BATS_FLAGS+=("--formatter" "pretty")
else
    BATS_FLAGS+=("--formatter" "tap")
fi

# ---------------------------------------------------------------------------
# run_suite <label> <file>...
#   Spin up a fresh container and run the named BATS files inside it.
# ---------------------------------------------------------------------------

run_suite() {
    local label="$1"; shift
    local files=("$@")

    printf '\n=== Suite: %s ===\n' "${label}"

    docker run --rm -t "${IMAGE_TAG}" \
        bash -euo pipefail -c '
            cd /etc/.pihole/test
            exec libs/bats/bin/bats "$@"
        ' bash "${BATS_FLAGS[@]}" "${files[@]}"
}

# ---------------------------------------------------------------------------
# Run both suites; collect exit codes so both always run even if one fails.
# ---------------------------------------------------------------------------

rc=0
run_suite "mock and function tests" "${SUITE_1[@]}" || rc=$?
run_suite "fresh install"           "${SUITE_2[@]}" || rc=$?
exit ${rc}
