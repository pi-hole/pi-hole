"""Tests for the Pi-hole agent safety guardrails.

These tests validate domain protection, rate limiting, blocking policy,
and audit logging without requiring a running Pi-hole instance.
"""

import json
import os
import tempfile
import time

import pytest

# Add the agent package to the path
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "advanced", "Scripts"))

from pihole_agent.config import SafetyConfig
from pihole_agent.core.safety import SafetyGuard, SafetyError


@pytest.fixture
def safety_config(tmp_path):
    """Create a SafetyConfig with a temp protected domains file."""
    protected_file = tmp_path / "protected_domains.list"
    protected_file.write_text("custom-protected.example.com\nmy-dns.local\n")
    return SafetyConfig(
        blocking_mode="confirm",
        protected_domains_file=str(protected_file),
        rate_limit_per_minute=3,
        rate_limit_per_hour=10,
        auto_block_confidence=0.95,
    )


@pytest.fixture
def guard(safety_config):
    """Create a SafetyGuard with test config."""
    return SafetyGuard(safety_config)


# ── Domain Protection ────────────────────────────────────────


class TestDomainProtection:
    def test_blocks_default_protected_domain(self, guard):
        """Default protected domains (dns.google, etc.) cannot be blocked."""
        with pytest.raises(SafetyError, match="protected"):
            guard.check_domain_protection("dns.google")

    def test_blocks_subdomain_of_protected(self, guard):
        """Subdomains of protected domains are also protected."""
        with pytest.raises(SafetyError, match="protected"):
            guard.check_domain_protection("sub.dns.google")

    def test_blocks_user_protected_domain(self, guard):
        """Domains from the user's protected_domains.list are protected."""
        with pytest.raises(SafetyError, match="protected"):
            guard.check_domain_protection("custom-protected.example.com")

    def test_allows_unprotected_domain(self, guard):
        """Non-protected domains pass the check without error."""
        guard.check_domain_protection("ads.example.com")  # should not raise

    def test_allows_similar_but_different_domain(self, guard):
        """A domain that contains a protected name but isn't a subdomain passes."""
        guard.check_domain_protection("notdns.google.evil.com")  # should not raise

    def test_case_insensitive(self, guard):
        """Protection checks are case-insensitive."""
        with pytest.raises(SafetyError):
            guard.check_domain_protection("DNS.GOOGLE")

    def test_protects_pihole_itself(self, guard):
        """Pi-hole's own domains are protected by default."""
        with pytest.raises(SafetyError):
            guard.check_domain_protection("pi-hole.net")

    def test_protects_os_update_domains(self, guard):
        """OS update servers are protected by default."""
        for domain in [
            "windowsupdate.com",
            "archive.ubuntu.com",
            "deb.debian.org",
        ]:
            with pytest.raises(SafetyError):
                guard.check_domain_protection(domain)

    def test_missing_protected_file_uses_defaults(self, tmp_path):
        """If the protected domains file doesn't exist, defaults still apply."""
        config = SafetyConfig(
            protected_domains_file=str(tmp_path / "nonexistent.list"),
        )
        g = SafetyGuard(config)
        with pytest.raises(SafetyError):
            g.check_domain_protection("dns.google")
        # But unprotected domains still pass
        g.check_domain_protection("ads.example.com")


# ── Rate Limiting ─────────────────────────────────────────────


class TestRateLimiting:
    def test_allows_within_limit(self, guard):
        """Actions within the rate limit pass."""
        guard.check_rate_limit("block")
        guard.check_rate_limit("block")
        guard.check_rate_limit("block")
        # 3 allowed (limit is 3/min)

    def test_blocks_exceeding_minute_limit(self, guard):
        """Exceeding per-minute limit raises SafetyError."""
        for _ in range(3):
            guard.check_rate_limit("block")
        with pytest.raises(SafetyError, match="per minute"):
            guard.check_rate_limit("block")

    def test_blocks_exceeding_hour_limit(self, tmp_path):
        """Exceeding per-hour limit raises SafetyError."""
        config = SafetyConfig(
            protected_domains_file=str(tmp_path / "none.list"),
            rate_limit_per_minute=100,  # high per-minute so we hit hourly first
            rate_limit_per_hour=5,
        )
        g = SafetyGuard(config)
        for _ in range(5):
            g.check_rate_limit("block")
        with pytest.raises(SafetyError, match="per hour"):
            g.check_rate_limit("block")


# ── Blocking Policy ───────────────────────────────────────────


class TestBlockingPolicy:
    def test_alert_only_denies_mutations(self, tmp_path):
        """alert_only mode denies all mutating operations."""
        config = SafetyConfig(
            blocking_mode="alert_only",
            protected_domains_file=str(tmp_path / "none.list"),
        )
        g = SafetyGuard(config)
        assert g.check_blocking_policy("block_domain") == "deny"
        assert g.check_blocking_policy("unblock_domain") == "deny"
        assert g.check_blocking_policy("disable_blocking") == "deny"

    def test_confirm_mode_returns_confirm(self, guard):
        """confirm mode returns 'confirm' for mutating operations."""
        assert guard.check_blocking_policy("block_domain") == "confirm"
        assert guard.check_blocking_policy("unblock_domain") == "confirm"

    def test_auto_all_allows_everything(self, tmp_path):
        """auto_all mode allows all mutating operations."""
        config = SafetyConfig(
            blocking_mode="auto_all",
            protected_domains_file=str(tmp_path / "none.list"),
        )
        g = SafetyGuard(config)
        assert g.check_blocking_policy("block_domain") == "allow"

    def test_auto_high_confidence_allows_above_threshold(self, tmp_path):
        """auto_high_confidence allows when confidence >= threshold."""
        config = SafetyConfig(
            blocking_mode="auto_high_confidence",
            auto_block_confidence=0.95,
            protected_domains_file=str(tmp_path / "none.list"),
        )
        g = SafetyGuard(config)
        assert g.check_blocking_policy("block_domain", confidence=0.97) == "allow"

    def test_auto_high_confidence_denies_below_threshold(self, tmp_path):
        """auto_high_confidence denies when confidence < threshold."""
        config = SafetyConfig(
            blocking_mode="auto_high_confidence",
            auto_block_confidence=0.95,
            protected_domains_file=str(tmp_path / "none.list"),
        )
        g = SafetyGuard(config)
        assert g.check_blocking_policy("block_domain", confidence=0.5) == "deny"

    def test_read_only_tools_always_allowed(self, guard):
        """Non-mutating tools are always allowed regardless of mode."""
        assert guard.check_blocking_policy("get_stats_summary") == "allow"
        assert guard.check_blocking_policy("search_adlists") == "allow"
        assert guard.check_blocking_policy("detect_anomalous_domains") == "allow"


# ── Mutating Tool Detection ──────────────────────────────────


class TestMutatingDetection:
    def test_block_domain_is_mutating(self, guard):
        assert guard.is_mutating("block_domain") is True

    def test_unblock_domain_is_mutating(self, guard):
        assert guard.is_mutating("unblock_domain") is True

    def test_enable_blocking_is_mutating(self, guard):
        assert guard.is_mutating("enable_blocking") is True

    def test_disable_blocking_is_mutating(self, guard):
        assert guard.is_mutating("disable_blocking") is True

    def test_get_stats_is_not_mutating(self, guard):
        assert guard.is_mutating("get_stats_summary") is False

    def test_search_adlists_is_not_mutating(self, guard):
        assert guard.is_mutating("search_adlists") is False


# ── Audit Logging ─────────────────────────────────────────────


class TestAuditLogging:
    def test_log_action_records_entry(self, guard):
        """log_action stores entries in memory."""
        guard.log_action("mcp", "claude", "block_domain", "test.com", "testing", "OK")
        actions = guard.get_recent_actions(10)
        assert len(actions) == 1
        assert actions[0]["action"] == "block_domain"
        assert actions[0]["target"] == "test.com"
        assert actions[0]["source"] == "mcp"
        assert actions[0]["status"] == "OK"

    def test_get_recent_actions_limits(self, guard):
        """get_recent_actions respects the n parameter."""
        for i in range(5):
            guard.log_action("cli", "test", "block_domain", f"d{i}.com", "", "OK")
        assert len(guard.get_recent_actions(3)) == 3
        assert len(guard.get_recent_actions(10)) == 5

    def test_get_rollback_actions_filters_mutating(self, guard):
        """get_rollback_actions only returns mutating actions."""
        guard.log_action("mcp", "claude", "get_stats", "global", "", "OK")
        guard.log_action("mcp", "claude", "block_domain", "a.com", "", "OK")
        guard.log_action("mcp", "claude", "search_adlists", "b.com", "", "OK")
        guard.log_action("mcp", "claude", "unblock_domain", "c.com", "", "OK")

        rollback = guard.get_rollback_actions(5)
        assert len(rollback) == 2
        assert rollback[0]["action"] == "block_domain"
        assert rollback[1]["action"] == "unblock_domain"

    def test_log_entry_has_timestamp(self, guard):
        """Audit entries include ISO format timestamps."""
        guard.log_action("mcp", "claude", "block_domain", "test.com", "", "OK")
        entry = guard.get_recent_actions(1)[0]
        assert "timestamp" in entry
        assert "T" in entry["timestamp"]  # ISO format
