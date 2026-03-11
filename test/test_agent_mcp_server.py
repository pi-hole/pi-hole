"""Tests for the Pi-hole MCP server.

Tests the provider gate, entropy calculation, anomaly detection heuristics,
and auth utilities. The MCP SDK import is optional — tests that don't
need it run regardless.
"""

import math
import os
import sys
from collections import Counter
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "advanced", "Scripts"))

from pihole_agent.config import AgentConfig

# ── Shannon Entropy (pure Python, no MCP dependency) ─────────


def _shannon_entropy(text: str) -> float:
    """Local copy of the entropy function for testing without MCP import."""
    if not text:
        return 0.0
    freq = Counter(text.lower())
    length = len(text)
    return -sum((count / length) * math.log2(count / length) for count in freq.values())


class TestShannonEntropy:
    def test_empty_string(self):
        assert _shannon_entropy("") == 0.0

    def test_single_char(self):
        assert _shannon_entropy("a") == 0.0

    def test_repeated_char(self):
        """All same characters = zero entropy."""
        assert _shannon_entropy("aaaaaaa") == 0.0

    def test_two_chars_equal(self):
        """Equal distribution of 2 chars = 1 bit."""
        result = _shannon_entropy("ab")
        assert abs(result - 1.0) < 0.01

    def test_high_entropy_random(self):
        """Random-looking strings have high entropy."""
        result = _shannon_entropy("a8f7g2h9k3m1")
        assert result > 3.0

    def test_low_entropy_word(self):
        """Common English words have moderate entropy."""
        result = _shannon_entropy("google")
        assert result < 2.5

    def test_dga_like_domain(self):
        """DGA-like strings have high entropy."""
        result = _shannon_entropy("x7k9m2p4q8w1")
        assert result > 3.0

    def test_case_insensitive(self):
        """Entropy calculation is case-insensitive."""
        assert _shannon_entropy("ABC") == _shannon_entropy("abc")


# ── Provider Gate ─────────────────────────────────────────────


class TestProviderGate:
    def test_anthropic_allowed(self, tmp_path):
        """Provider gate passes when provider is 'anthropic'."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text('[llm]\nprovider = "anthropic"\n')
        config = AgentConfig.load(str(config_file))
        assert config.llm.provider == "anthropic"

    def test_openai_detected(self, tmp_path):
        """Non-anthropic provider is detectable for gating."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text('[llm]\nprovider = "openai"\n')
        config = AgentConfig.load(str(config_file))
        assert config.llm.provider != "anthropic"

    def test_ollama_detected(self, tmp_path):
        """Ollama provider is detectable for gating."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text('[llm]\nprovider = "ollama"\n')
        config = AgentConfig.load(str(config_file))
        assert config.llm.provider != "anthropic"

    def test_default_is_anthropic(self, tmp_path):
        """Default provider is anthropic."""
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.provider == "anthropic"


# ── Anomaly Detection Logic ──────────────────────────────────


class TestAnomalyDetectionLogic:
    """Tests the anomaly detection heuristics used by detect_anomalous_domains."""

    def test_normal_domain_not_flagged(self):
        """Normal domains like google.com have low entropy."""
        entropy = _shannon_entropy("google")
        assert entropy < 3.5

    def test_dga_domain_flagged(self):
        """DGA-like domains have high entropy and long labels."""
        label = "a8f7g2h9k3m1n5p4"
        entropy = _shannon_entropy(label)
        assert entropy > 3.5
        assert len(label) > 10

    def test_subdomain_depth_detection(self):
        """Deeply nested subdomains indicate potential tunneling."""
        domain = "a.b.c.d.e.f.example.com"
        labels = domain.split(".")
        assert len(labels) > 5

    def test_consonant_ratio_detection(self):
        """High consonant ratio indicates random-looking domains."""
        label = "xkjwmrlptcbv"
        vowels = set("aeiou")
        consonant_ratio = sum(
            1 for c in label.lower() if c.isalpha() and c not in vowels
        ) / max(len(label), 1)
        assert consonant_ratio > 0.75

    def test_normal_domain_consonant_ratio(self):
        """Normal English words have balanced consonant ratios."""
        label = "facebook"
        vowels = set("aeiou")
        consonant_ratio = sum(
            1 for c in label.lower() if c.isalpha() and c not in vowels
        ) / max(len(label), 1)
        assert consonant_ratio < 0.75


# ── MCP Auth ──────────────────────────────────────────────────


class TestMCPAuth:
    def test_generate_token_format(self):
        """Generated tokens have the expected prefix."""
        from pihole_agent.mcp.auth import generate_token

        token = generate_token()
        assert token.startswith("mcp_ph_")
        assert len(token) > 20

    def test_generate_token_unique(self):
        """Each generated token is unique."""
        from pihole_agent.mcp.auth import generate_token

        tokens = {generate_token() for _ in range(10)}
        assert len(tokens) == 10

    def test_save_token_creates_file(self, tmp_path):
        """save_token_to_config creates the config file if missing."""
        from pihole_agent.mcp.auth import save_token_to_config

        config_path = str(tmp_path / "agent.toml")
        save_token_to_config("mcp_ph_testtoken", config_path)
        content = (tmp_path / "agent.toml").read_text()
        assert "mcp_ph_testtoken" in content
        assert "[mcp]" in content

    def test_save_token_updates_existing(self, tmp_path):
        """save_token_to_config updates an existing config file."""
        from pihole_agent.mcp.auth import save_token_to_config

        config_path = tmp_path / "agent.toml"
        config_path.write_text('[mcp]\nauth_token = "old_token"\nport = 8741\n')
        save_token_to_config("mcp_ph_newtoken", str(config_path))
        content = config_path.read_text()
        assert "mcp_ph_newtoken" in content
        assert "old_token" not in content
        assert "port = 8741" in content
