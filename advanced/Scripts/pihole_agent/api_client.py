"""Python port of Pi-hole's api.sh — FTL REST API client.

Mirrors the authentication and request patterns from advanced/Scripts/api.sh:
  - TestAPIAvailability() → discover_api()
  - LoginAPI()            → login()
  - GetFTLData()          → get()
  - PostFTLData()         → post()
  - LogoutAPI()           → logout()
"""

import json
import subprocess
from pathlib import Path
from typing import Any, Optional

import requests


CLI_PW_PATH = "/etc/pihole/cli_pw"


class PiholeAPIError(Exception):
    """Raised when the FTL API returns an error."""
    pass


class PiholeAPIClient:
    """Context-managed HTTP client for the Pi-hole FTL REST API."""

    def __init__(self, cli_pw_path: str = CLI_PW_PATH):
        self._cli_pw_path = cli_pw_path
        self._api_url: Optional[str] = None
        self._sid: Optional[str] = None

    def __enter__(self) -> "PiholeAPIClient":
        self._discover_api()
        self._login()
        return self

    def __exit__(self, *args: Any) -> None:
        self._logout()

    # ── API Discovery (mirrors TestAPIAvailability) ──

    def _discover_api(self) -> None:
        """Find the FTL API URL via DNS CHAOS query or config fallback."""
        dns_port = self._get_ftl_config("dns.port", "53")
        web_port = self._get_ftl_config("webserver.port", "80")

        # Try CHAOS TXT query (same as api.sh line 35)
        try:
            result = subprocess.run(
                ["dig", "+short", f"-p{dns_port}", "chaos", "txt", "local.api.ftl", "@127.0.0.1"],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0 and result.stdout.strip():
                urls = result.stdout.strip().replace('"', "").split("\n")
                for url in urls:
                    url = url.strip()
                    if url and not url.startswith("#"):
                        self._api_url = url
                        return
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

        # Fallback: construct URL from config
        self._api_url = f"http://127.0.0.1:{web_port}/api/"

    # ── Authentication (mirrors LoginAPI) ──

    def _login(self) -> None:
        """Authenticate using cli_pw file (same as api.sh LoginAPI)."""
        pw_path = Path(self._cli_pw_path)
        if not pw_path.exists():
            raise PiholeAPIError(f"CLI password file not found: {self._cli_pw_path}")

        password = pw_path.read_text().strip()

        resp = requests.post(
            f"{self._api_url}auth",
            json={"password": password},
            timeout=10,
        )
        if resp.status_code == 401:
            raise PiholeAPIError("Authentication failed — invalid password")

        data = resp.json()
        session = data.get("session", {})
        self._sid = session.get("sid")
        if not self._sid:
            raise PiholeAPIError("No session ID returned from auth endpoint")

    def _logout(self) -> None:
        """Destroy the session (mirrors LogoutAPI)."""
        if not self._sid or not self._api_url:
            return
        try:
            requests.delete(
                f"{self._api_url}auth",
                headers={"sid": self._sid},
                timeout=5,
            )
        except requests.RequestException:
            pass
        self._sid = None

    # ── Data Access (mirrors GetFTLData / PostFTLData) ──

    def get(self, endpoint: str) -> Any:
        """HTTP GET with session header. Returns parsed JSON."""
        resp = requests.get(
            f"{self._api_url}{endpoint}",
            headers={"sid": self._sid, "Accept": "application/json"},
            timeout=30,
        )
        if resp.status_code == 401:
            raise PiholeAPIError("Session expired or unauthorized")
        resp.raise_for_status()
        if resp.status_code == 204:
            return {}
        return resp.json()

    def post(self, endpoint: str, data: dict) -> Any:
        """HTTP POST with session header. Returns parsed JSON."""
        resp = requests.post(
            f"{self._api_url}{endpoint}",
            headers={"sid": self._sid, "Accept": "application/json"},
            json=data,
            timeout=30,
        )
        if resp.status_code == 401:
            raise PiholeAPIError("Session expired or unauthorized")
        resp.raise_for_status()
        if resp.status_code == 204:
            return {}
        return resp.json()

    def delete(self, endpoint: str, data: Optional[dict] = None) -> Any:
        """HTTP DELETE with session header."""
        resp = requests.delete(
            f"{self._api_url}{endpoint}",
            headers={"sid": self._sid, "Accept": "application/json"},
            json=data,
            timeout=30,
        )
        resp.raise_for_status()
        if resp.status_code == 204:
            return {}
        return resp.json()

    # ── Helpers ──

    @staticmethod
    def _get_ftl_config(key: str, default: str = "") -> str:
        """Get a value from pihole-FTL config (mirrors getFTLConfigValue)."""
        try:
            result = subprocess.run(
                ["pihole-FTL", "--config", "-q", key],
                capture_output=True, text=True, timeout=5,
            )
            value = result.stdout.strip()
            return value if value else default
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return default
