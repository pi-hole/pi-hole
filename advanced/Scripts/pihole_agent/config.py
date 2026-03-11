"""Agent configuration management.

Reads from /etc/pihole/agent.toml with environment variable overrides.
"""

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

DEFAULT_CONFIG_PATH = "/etc/pihole/agent.toml"

DEFAULTS = {
    "llm": {
        "provider": "anthropic",
        "api_key": "",
        "model": "claude-sonnet-4-20250514",
        "base_url": "",
        "max_tokens": 4096,
    },
    "safety": {
        "blocking_mode": "alert_only",
        "protected_domains_file": "/etc/pihole/agent_protected_domains.list",
        "rate_limit_per_minute": 10,
        "rate_limit_per_hour": 100,
        "auto_block_confidence": 0.95,
    },
    "monitor": {
        "poll_interval_seconds": 60,
        "analysis_window_minutes": 15,
        "alert_log": "/var/log/pihole/agent_alerts.log",
        "state_file": "/etc/pihole/agent_monitor_state.json",
    },
    "mcp": {
        "enabled": True,
        "transport": "stdio",
        "port": 8741,
        "host": "127.0.0.1",
        "auth_token": "",
    },
    "logging": {
        "audit_log": "/var/log/pihole/agent_audit.log",
        "level": "info",
    },
}


@dataclass
class LLMConfig:
    provider: str = "anthropic"
    api_key: str = ""
    model: str = "claude-sonnet-4-20250514"
    base_url: str = ""
    max_tokens: int = 4096


@dataclass
class SafetyConfig:
    blocking_mode: str = "alert_only"
    protected_domains_file: str = "/etc/pihole/agent_protected_domains.list"
    rate_limit_per_minute: int = 10
    rate_limit_per_hour: int = 100
    auto_block_confidence: float = 0.95


@dataclass
class MonitorConfig:
    poll_interval_seconds: int = 60
    analysis_window_minutes: int = 15
    alert_log: str = "/var/log/pihole/agent_alerts.log"
    state_file: str = "/etc/pihole/agent_monitor_state.json"


@dataclass
class MCPConfig:
    enabled: bool = True
    transport: str = "stdio"
    port: int = 8741
    host: str = "127.0.0.1"
    auth_token: str = ""


@dataclass
class LoggingConfig:
    audit_log: str = "/var/log/pihole/agent_audit.log"
    level: str = "info"


@dataclass
class AgentConfig:
    llm: LLMConfig = field(default_factory=LLMConfig)
    safety: SafetyConfig = field(default_factory=SafetyConfig)
    monitor: MonitorConfig = field(default_factory=MonitorConfig)
    mcp: MCPConfig = field(default_factory=MCPConfig)
    logging: LoggingConfig = field(default_factory=LoggingConfig)

    @classmethod
    def load(cls, path: str = DEFAULT_CONFIG_PATH) -> "AgentConfig":
        """Load configuration from TOML file with env var overrides."""
        raw = dict(DEFAULTS)

        config_path = Path(path)
        if config_path.exists() and tomllib is not None:
            with open(config_path, "rb") as f:
                file_config = tomllib.load(f)
            for section, values in file_config.items():
                if section in raw and isinstance(values, dict):
                    raw[section] = {**raw[section], **values}

        # Environment variable overrides
        env_api_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get(
            "OPENAI_API_KEY", ""
        )
        if env_api_key:
            raw["llm"]["api_key"] = env_api_key

        mcp_token = os.environ.get("PIHOLE_MCP_TOKEN", "")
        if mcp_token:
            raw["mcp"]["auth_token"] = mcp_token

        return cls(
            llm=LLMConfig(**raw["llm"]),
            safety=SafetyConfig(**raw["safety"]),
            monitor=MonitorConfig(**raw["monitor"]),
            mcp=MCPConfig(**raw["mcp"]),
            logging=LoggingConfig(**raw["logging"]),
        )

    def safety_dict(self) -> dict:
        """Return safety config as a dict for MCP resource exposure."""
        return {
            "blocking_mode": self.safety.blocking_mode,
            "rate_limit_per_minute": self.safety.rate_limit_per_minute,
            "rate_limit_per_hour": self.safety.rate_limit_per_hour,
            "auto_block_confidence": self.safety.auto_block_confidence,
        }
