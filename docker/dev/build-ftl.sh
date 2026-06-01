#!/usr/bin/env bash
# Build the modified pihole-FTL binary and hot-swap it into the running
# pihole-dev container.
#
# Run once after first checkout, and whenever C source files change.
# Requires: cmake, gcc, and the FTL build dependencies (see DEPS below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FTL_SRC="${REPO_ROOT}/pihole-FTL"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Install build dependencies (Ubuntu/Debian) ──────────────────────────
DEPS=(cmake gcc libgmp-dev libnettle-dev libidn2-dev libunistring-dev)
echo "[build-ftl] Installing build dependencies..."
sudo apt-get install -y -q "${DEPS[@]}"

# ── 2. Build FTL ─────────────────────────────────────────────────────────
echo "[build-ftl] Building pihole-FTL..."
cd "${FTL_SRC}"
bash build.sh
BINARY="${FTL_SRC}/cmake/pihole-FTL"
echo "[build-ftl] Binary: ${BINARY}"

# ── 3. Uncomment the FTL volume mount in docker-compose.yml ──────────────
# Enable the commented-out FTL binary mount so the container uses our build.
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
sed -i 's|# - \.\.\./\.\.\./pihole-FTL/cmake/pihole-FTL:/usr/bin/pihole-FTL|- ../../../pihole-FTL/cmake/pihole-FTL:/usr/bin/pihole-FTL|' "${COMPOSE_FILE}"
echo "[build-ftl] Enabled FTL binary mount in docker-compose.yml"

# ── 4. Restart the container to pick up the new binary ───────────────────
echo "[build-ftl] Restarting pihole-dev container..."
cd "${COMPOSE_DIR}"
docker compose down
docker compose up -d

echo ""
echo "[build-ftl] Done. The container is using your locally built pihole-FTL."
echo "  Test the new API param:"
echo "    curl -s 'http://127.0.0.1:8080/api/stats/top_domains?blocked=true&list=1'"
echo ""
echo "  Admin UI: http://127.0.0.1:8080/admin/"
