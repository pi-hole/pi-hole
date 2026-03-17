#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Distro selection
# ---------------------------------------------------------------------------

if [[ -z "${DISTRO:-}" ]]; then
    echo "Error: DISTRO is required."
    echo "Example: DISTRO=debian_12 bash test/run.sh"
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

# ---------------------------------------------------------------------------
# Install BATS and helper libraries (on-demand, not committed)
# ---------------------------------------------------------------------------

mkdir -p libs
if [[ ! -d libs/bats ]]; then
    echo "Cloning bats-core..."
    git clone --depth=1 --quiet https://github.com/bats-core/bats-core libs/bats
fi
if [[ ! -d libs/bats-support ]]; then
    echo "Cloning bats-support..."
    git clone --depth=1 --quiet https://github.com/bats-core/bats-support libs/bats-support
fi
if [[ ! -d libs/bats-assert ]]; then
    echo "Cloning bats-assert..."
    git clone --depth=1 --quiet https://github.com/bats-core/bats-assert libs/bats-assert
fi

BATS="${BATS:-libs/bats/bin/bats}"

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------

export IMAGE_TAG DISTRO DISTRO_FAMILY

TEST_FILES=(
    test_automated_install.bats
    test_ftl.bats
    test_network.bats
    test_utils.bats
)
[[ "$DISTRO_FAMILY" == "rhel" ]] && TEST_FILES+=(test_selinux.bats)

# Use pretty output only when stdout is a real terminal; fall back to TAP in CI.
# Parallelise across files with --jobs when GNU parallel is available.
BATS_FLAGS=()
[[ -t 1 ]] && BATS_FLAGS+=("-p")
command -v parallel > /dev/null 2>&1 && BATS_FLAGS+=("--jobs" "$(nproc)")
"$BATS" "${BATS_FLAGS[@]}" "${TEST_FILES[@]}"
