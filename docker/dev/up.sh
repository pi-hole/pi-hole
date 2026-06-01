#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not accessible. Run once (then log out/in, or: newgrp docker):"
  echo "  sudo usermod -aG docker \"\$USER\""
  exit 1
fi

docker compose pull
docker compose up -d

echo ""
echo "Pi-hole dev container is starting."
echo "  Admin UI:  http://127.0.0.1:8080/admin/"
echo "  Password:  see FTLCONF_webserver_api_password in .env (default: devpassword)"
echo ""
echo "Quick checks:"
echo "  docker compose logs -f pihole"
echo "  dig @127.0.0.1 -p 8053 doubleclick.net +short"
echo "  curl -s http://127.0.0.1:8080/admin/ | head -5"
