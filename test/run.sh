#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
    ls _*.Dockerfile | sed 's/^_//;s/\.Dockerfile$//' | sort
    exit 1
fi

DOCKERFILE="_${DISTRO}.Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
    echo "Error: Dockerfile not found: $DOCKERFILE"
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
DISTRO_FAMILY=$(distro_family "$DISTRO")

TEST_FILES=(
    test_automated_install.bats
    test_installer_ftl.bats
    test_network.bats
    test_utils.bats
)
[[ "$DISTRO_FAMILY" == "rhel" ]] && TEST_FILES+=(test_selinux.bats)

# ---------------------------------------------------------------------------
# Build the test image
# ---------------------------------------------------------------------------

IMAGE_TAG="pihole_test:${DISTRO}"

docker buildx build \
    --load \
    --progress plain \
    -f "$DOCKERFILE" \
    -t "$IMAGE_TAG" \
    ../

docker run --rm -t \
    -e BATS_CORE_REF="${BATS_CORE_REF:-v1.13.0}" \
    -e BATS_SUPPORT_REF="${BATS_SUPPORT_REF:-v0.3.0}" \
    -e BATS_ASSERT_REF="${BATS_ASSERT_REF:-v2.2.4}" \
    "$IMAGE_TAG" \
    bash -euo pipefail -c '
        cd /etc/.pihole/test

        test_files=("$@")

        mkdir -p libs
        if [[ ! -d libs/bats ]]; then
            git clone --depth=1 --single-branch --branch "${BATS_CORE_REF}" --quiet \
                https://github.com/bats-core/bats-core libs/bats
        fi
        if [[ ! -d libs/bats-support ]]; then
            git clone --depth=1 --single-branch --branch "${BATS_SUPPORT_REF}" --quiet \
                https://github.com/bats-core/bats-support libs/bats-support
        fi
        if [[ ! -d libs/bats-assert ]]; then
            git clone --depth=1 --single-branch --branch "${BATS_ASSERT_REF}" --quiet \
                https://github.com/bats-core/bats-assert libs/bats-assert
        fi

        # Installer tests can mutate /etc/.pihole, so execute from a copied
        # working tree to keep test files stable for the full run.
        rm -rf /tmp/tests
        mkdir -p /tmp/tests/libs /tmp/tests/helpers
        cp -a libs/bats /tmp/tests/libs/
        cp -a libs/bats-support /tmp/tests/libs/
        cp -a libs/bats-assert /tmp/tests/libs/
        cp -a helpers/mocks.bash /tmp/tests/helpers/

        for f in "${test_files[@]}"; do
            cp -a "$f" /tmp/tests/
        done

        cd /tmp/tests
        exec libs/bats/bin/bats -p --print-output-on-failure "${test_files[@]##*/}"
    ' bash "${TEST_FILES[@]}"
