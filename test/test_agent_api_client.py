"""Tests for the Pi-hole agent FTL API client.

Tests client construction, authentication flow, and request methods
using mocked HTTP responses. No running Pi-hole required.
"""

import json
import os
import sys
from unittest.mock import MagicMock, patch, mock_open

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "advanced", "Scripts"))

from pihole_agent.api_client import PiholeAPIClient, PiholeAPIError

# ── Fixtures ──────────────────────────────────────────────────


@pytest.fixture
def cli_pw_file(tmp_path):
    """Create a temporary cli_pw file."""
    pw_file = tmp_path / "cli_pw"
    pw_file.write_text("test-password-hash")
    return str(pw_file)


@pytest.fixture
def client(cli_pw_file):
    """Create a PiholeAPIClient with test cli_pw path."""
    return PiholeAPIClient(cli_pw_path=cli_pw_file)


# ── Construction ──────────────────────────────────────────────


class TestClientConstruction:
    def test_creates_with_default_path(self):
        """Client can be created with default cli_pw path."""
        c = PiholeAPIClient()
        assert c._cli_pw_path == "/etc/pihole/cli_pw"

    def test_creates_with_custom_path(self, cli_pw_file):
        """Client accepts a custom cli_pw path."""
        c = PiholeAPIClient(cli_pw_path=cli_pw_file)
        assert c._cli_pw_path == cli_pw_file

    def test_initial_state(self, client):
        """Client starts with no API URL or session."""
        assert client._api_url is None
        assert client._sid is None


# ── API Discovery ─────────────────────────────────────────────


class TestAPIDiscovery:
    @patch("pihole_agent.api_client.subprocess.run")
    def test_discovers_via_dns_chaos(self, mock_run, client):
        """API URL is discovered via DNS CHAOS TXT query."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout='"http://127.0.0.1:8080/api/"\n',
        )
        client._discover_api()
        assert client._api_url == "http://127.0.0.1:8080/api/"

    @patch("pihole_agent.api_client.subprocess.run")
    def test_falls_back_to_config(self, mock_run, client):
        """Falls back to constructed URL when DNS query fails."""
        mock_run.side_effect = FileNotFoundError("dig not found")
        client._discover_api()
        # Should construct from defaults
        assert client._api_url is not None
        assert "api/" in client._api_url


# ── Authentication ────────────────────────────────────────────


class TestAuthentication:
    @patch("pihole_agent.api_client.requests.post")
    def test_login_success(self, mock_post, client):
        """Successful login stores the session ID."""
        mock_post.return_value = MagicMock(
            status_code=200,
            json=lambda: {"session": {"sid": "test-sid-123"}},
        )
        client._api_url = "http://127.0.0.1/api/"
        client._login()
        assert client._sid == "test-sid-123"

    @patch("pihole_agent.api_client.requests.post")
    def test_login_401_raises(self, mock_post, client):
        """401 response raises PiholeAPIError."""
        mock_post.return_value = MagicMock(status_code=401)
        client._api_url = "http://127.0.0.1/api/"
        with pytest.raises(PiholeAPIError, match="Authentication failed"):
            client._login()

    def test_login_missing_pw_file_raises(self, tmp_path):
        """Missing cli_pw file raises PiholeAPIError."""
        c = PiholeAPIClient(cli_pw_path=str(tmp_path / "nonexistent"))
        c._api_url = "http://127.0.0.1/api/"
        with pytest.raises(PiholeAPIError, match="not found"):
            c._login()

    @patch("pihole_agent.api_client.requests.post")
    def test_login_no_sid_raises(self, mock_post, client):
        """Response without session ID raises PiholeAPIError."""
        mock_post.return_value = MagicMock(
            status_code=200,
            json=lambda: {"session": {}},
        )
        client._api_url = "http://127.0.0.1/api/"
        with pytest.raises(PiholeAPIError, match="No session ID"):
            client._login()


# ── Logout ────────────────────────────────────────────────────


class TestLogout:
    @patch("pihole_agent.api_client.requests.delete")
    def test_logout_clears_sid(self, mock_delete, client):
        """Logout clears the session ID."""
        mock_delete.return_value = MagicMock(status_code=204)
        client._api_url = "http://127.0.0.1/api/"
        client._sid = "test-sid"
        client._logout()
        assert client._sid is None

    def test_logout_noop_without_sid(self, client):
        """Logout is a no-op if no session exists."""
        client._logout()  # should not raise


# ── GET/POST Requests ─────────────────────────────────────────


class TestRequests:
    @patch("pihole_agent.api_client.requests.get")
    def test_get_success(self, mock_get, client):
        """GET request returns parsed JSON."""
        mock_get.return_value = MagicMock(
            status_code=200,
            json=lambda: {"queries": 1234},
        )
        client._api_url = "http://127.0.0.1/api/"
        client._sid = "test-sid"
        result = client.get("stats/summary")
        assert result == {"queries": 1234}
        # Verify SID header was sent
        call_kwargs = mock_get.call_args
        assert call_kwargs.kwargs["headers"]["sid"] == "test-sid"

    @patch("pihole_agent.api_client.requests.get")
    def test_get_401_raises(self, mock_get, client):
        """GET with 401 response raises PiholeAPIError."""
        mock_get.return_value = MagicMock(status_code=401)
        client._api_url = "http://127.0.0.1/api/"
        client._sid = "expired-sid"
        with pytest.raises(PiholeAPIError, match="unauthorized"):
            client.get("stats/summary")

    @patch("pihole_agent.api_client.requests.get")
    def test_get_204_returns_empty(self, mock_get, client):
        """GET with 204 No Content returns empty dict."""
        mock_get.return_value = MagicMock(status_code=204)
        mock_get.return_value.raise_for_status = MagicMock()
        client._api_url = "http://127.0.0.1/api/"
        client._sid = "test-sid"
        result = client.get("some/endpoint")
        assert result == {}

    @patch("pihole_agent.api_client.requests.post")
    def test_post_success(self, mock_post, client):
        """POST request sends data and returns parsed JSON."""
        mock_post.return_value = MagicMock(
            status_code=200,
            json=lambda: {"processed": {"success": True}},
        )
        client._api_url = "http://127.0.0.1/api/"
        client._sid = "test-sid"
        result = client.post("domains/deny/exact", {"domain": "test.com"})
        assert result["processed"]["success"] is True
        # Verify data was sent
        call_kwargs = mock_post.call_args
        assert call_kwargs.kwargs["json"] == {"domain": "test.com"}


# ── Context Manager ───────────────────────────────────────────


class TestContextManager:
    @patch("pihole_agent.api_client.requests.delete")
    @patch("pihole_agent.api_client.requests.post")
    @patch("pihole_agent.api_client.requests.get")
    @patch("pihole_agent.api_client.subprocess.run")
    def test_context_manager_lifecycle(
        self, mock_subprocess, mock_get, mock_post, mock_delete, cli_pw_file
    ):
        """Context manager discovers API, logs in, and logs out."""
        # Setup mocks
        mock_subprocess.return_value = MagicMock(
            returncode=0,
            stdout='"http://127.0.0.1/api/"\n',
        )
        mock_post.return_value = MagicMock(
            status_code=200,
            json=lambda: {"session": {"sid": "ctx-sid"}},
        )
        mock_get.return_value = MagicMock(
            status_code=200,
            json=lambda: {"data": "test"},
        )
        mock_delete.return_value = MagicMock(status_code=204)

        with PiholeAPIClient(cli_pw_path=cli_pw_file) as c:
            assert c._sid == "ctx-sid"
            result = c.get("test")
            assert result == {"data": "test"}

        # Verify logout was called
        mock_delete.assert_called_once()


# ── FTL Config Helper ─────────────────────────────────────────


class TestFTLConfig:
    @patch("pihole_agent.api_client.subprocess.run")
    def test_get_ftl_config_value(self, mock_run):
        """_get_ftl_config returns the config value."""
        mock_run.return_value = MagicMock(returncode=0, stdout="53\n")
        result = PiholeAPIClient._get_ftl_config("dns.port", "53")
        assert result == "53"

    @patch("pihole_agent.api_client.subprocess.run")
    def test_get_ftl_config_fallback(self, mock_run):
        """_get_ftl_config returns default when command fails."""
        mock_run.side_effect = FileNotFoundError()
        result = PiholeAPIClient._get_ftl_config("dns.port", "53")
        assert result == "53"
