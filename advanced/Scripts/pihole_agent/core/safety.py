"""Safety guardrails for agent actions.

Enforces domain protection, rate limiting, audit logging, and
configurable blocking policy. Applied uniformly to CLI and MCP contexts.
"""

import json
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from pihole_agent.config import AgentConfig, SafetyConfig

# Domains that should never be blocked by agents
DEFAULT_PROTECTED_DOMAINS = {
    # DNS resolvers
    "dns.google",
    "dns.google.com",
    "dns.quad9.net",
    "cloudflare-dns.com",
    "one.one.one.one",
    # OS updates
    "windowsupdate.com",
    "update.microsoft.com",
    "updates.apple.com",
    "swscan.apple.com",
    "archive.ubuntu.com",
    "security.ubuntu.com",
    "deb.debian.org",
    "security.debian.org",
    "download.fedoraproject.org",
    # Package managers
    "pypi.org",
    "registry.npmjs.org",
    "rubygems.org",
    # Critical infrastructure
    "github.com",
    "raw.githubusercontent.com",
    "gitlab.com",
    "bitbucket.org",
    # Authentication
    "accounts.google.com",
    "login.microsoftonline.com",
    "auth0.com",
    "okta.com",
    # Pi-hole itself
    "pi.hole",
    "pi-hole.net",
}


class SafetyError(Exception):
    """Raised when a safety check fails."""

    pass


class SafetyGuard:
    """Enforces safety constraints on all agent actions."""

    MUTATING_TOOLS = {
        "block_domain",
        "unblock_domain",
        "block_regex",
        "enable_blocking",
        "disable_blocking",
    }

    def __init__(self, config: SafetyConfig) -> None:
        self._config = config
        self._protected_domains = self._load_protected_domains()
        self._action_log: deque = deque(maxlen=1000)
        self._minute_actions: deque = deque()
        self._hour_actions: deque = deque()

    @classmethod
    def from_config(cls, config: Optional[AgentConfig] = None) -> "SafetyGuard":
        if config is None:
            config = AgentConfig.load()
        return cls(config.safety)

    def _load_protected_domains(self) -> set[str]:
        """Load protected domains from default set + user file."""
        domains = set(DEFAULT_PROTECTED_DOMAINS)
        path = Path(self._config.protected_domains_file)
        if path.exists():
            for line in path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    domains.add(line.lower())
        return domains

    def check_domain_protection(self, domain: str) -> None:
        """Raise SafetyError if the domain is protected."""
        domain_lower = domain.lower()
        for protected in self._protected_domains:
            if domain_lower == protected or domain_lower.endswith(f".{protected}"):
                raise SafetyError(
                    f"Domain '{domain}' is protected and cannot be blocked. "
                    f"Matches protected entry: {protected}"
                )

    def check_rate_limit(self, action_type: str) -> None:
        """Raise SafetyError if rate limit is exceeded."""
        now = time.time()

        # Clean expired entries
        while self._minute_actions and self._minute_actions[0] < now - 60:
            self._minute_actions.popleft()
        while self._hour_actions and self._hour_actions[0] < now - 3600:
            self._hour_actions.popleft()

        if len(self._minute_actions) >= self._config.rate_limit_per_minute:
            raise SafetyError(
                f"Rate limit exceeded: {self._config.rate_limit_per_minute} actions per minute"
            )
        if len(self._hour_actions) >= self._config.rate_limit_per_hour:
            raise SafetyError(
                f"Rate limit exceeded: {self._config.rate_limit_per_hour} actions per hour"
            )

        self._minute_actions.append(now)
        self._hour_actions.append(now)

    def check_blocking_policy(self, tool_name: str, confidence: float = 1.0) -> str:
        """Check if the current blocking policy allows this action.

        Returns the policy decision: "allow", "confirm", or "deny".
        """
        if tool_name not in self.MUTATING_TOOLS:
            return "allow"

        mode = self._config.blocking_mode
        if mode == "auto_all":
            return "allow"
        elif mode == "auto_high_confidence":
            if confidence >= self._config.auto_block_confidence:
                return "allow"
            return "deny"
        elif mode == "confirm":
            return "confirm"
        else:  # alert_only
            return "deny"

    def is_mutating(self, tool_name: str) -> bool:
        return tool_name in self.MUTATING_TOOLS

    def log_action(
        self,
        source: str,
        agent: str,
        action: str,
        target: str,
        rationale: str,
        status: str = "OK",
    ) -> None:
        """Append to audit log."""
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": source,
            "agent": agent,
            "action": action,
            "target": target,
            "rationale": rationale,
            "status": status,
        }
        self._action_log.append(entry)

        # Write to file
        log_path = (
            Path(self._config.protected_domains_file).parent
            / ".."
            / "log"
            / "pihole"
            / "agent_audit.log"
        )
        # Use the config's audit log path via the parent AgentConfig if available
        try:
            config = AgentConfig.load()
            log_path = Path(config.logging.audit_log)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(log_path, "a") as f:
                f.write(json.dumps(entry) + "\n")
        except (OSError, PermissionError):
            pass

    def get_recent_actions(self, n: int = 20) -> list[dict]:
        """Get the last N audit log entries."""
        return list(self._action_log)[-n:]

    def get_rollback_actions(self, n: int = 1) -> list[dict]:
        """Get the last N mutating actions for rollback."""
        mutating = [a for a in self._action_log if a["action"] in self.MUTATING_TOOLS]
        return mutating[-n:]
