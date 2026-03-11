"""Tests for the Pi-hole agent configuration loader.

Validates TOML parsing, defaults, environment variable overrides,
and dataclass construction.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "advanced", "Scripts"))

from pihole_agent.config import (
    AgentConfig,
    LLMConfig,
    MCPConfig,
    SafetyConfig,
    MonitorConfig,
    LoggingConfig,
    DEFAULTS,
)

# ── Default Config ────────────────────────────────────────────


class TestDefaultConfig:
    def test_load_missing_file_uses_defaults(self, tmp_path):
        """Loading from a nonexistent path returns all defaults."""
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.provider == "anthropic"
        assert config.llm.model == "claude-sonnet-4-20250514"
        assert config.safety.blocking_mode == "alert_only"
        assert config.safety.rate_limit_per_minute == 10
        assert config.monitor.poll_interval_seconds == 60
        assert config.mcp.transport == "stdio"
        assert config.mcp.port == 8741
        assert config.logging.level == "info"

    def test_default_api_key_is_empty(self, tmp_path):
        """API key defaults to empty string."""
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.api_key == ""

    def test_default_mcp_host(self, tmp_path):
        """MCP defaults to localhost."""
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.mcp.host == "127.0.0.1"


# ── TOML File Loading ─────────────────────────────────────────


class TestTOMLLoading:
    def test_load_partial_config(self, tmp_path):
        """A TOML file with partial config merges with defaults."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text('[llm]\nprovider = "openai"\nmodel = "gpt-4"\n')
        config = AgentConfig.load(str(config_file))
        assert config.llm.provider == "openai"
        assert config.llm.model == "gpt-4"
        # Other defaults preserved
        assert config.llm.max_tokens == 4096
        assert config.safety.blocking_mode == "alert_only"

    def test_load_safety_config(self, tmp_path):
        """Safety section loads correctly from TOML."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text(
            '[safety]\nblocking_mode = "auto_all"\n' "rate_limit_per_minute = 50\n"
        )
        config = AgentConfig.load(str(config_file))
        assert config.safety.blocking_mode == "auto_all"
        assert config.safety.rate_limit_per_minute == 50
        # Default preserved
        assert config.safety.rate_limit_per_hour == 100

    def test_load_mcp_config(self, tmp_path):
        """MCP section loads correctly from TOML."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text(
            '[mcp]\ntransport = "http"\nport = 9999\n' 'host = "0.0.0.0"\n'
        )
        config = AgentConfig.load(str(config_file))
        assert config.mcp.transport == "http"
        assert config.mcp.port == 9999
        assert config.mcp.host == "0.0.0.0"

    def test_load_full_config(self, tmp_path):
        """A complete TOML config loads all sections."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text(
            '[llm]\nprovider = "openai"\napi_key = "sk-test"\n'
            'model = "gpt-4"\nbase_url = "http://localhost:11434/v1"\n'
            "max_tokens = 2048\n\n"
            '[safety]\nblocking_mode = "confirm"\n'
            "rate_limit_per_minute = 5\n"
            "rate_limit_per_hour = 50\n"
            "auto_block_confidence = 0.8\n\n"
            "[monitor]\npoll_interval_seconds = 30\n"
            "analysis_window_minutes = 10\n\n"
            '[mcp]\ntransport = "http"\nport = 9000\n\n'
            '[logging]\nlevel = "debug"\n'
        )
        config = AgentConfig.load(str(config_file))
        assert config.llm.provider == "openai"
        assert config.llm.api_key == "sk-test"
        assert config.llm.base_url == "http://localhost:11434/v1"
        assert config.llm.max_tokens == 2048
        assert config.safety.blocking_mode == "confirm"
        assert config.safety.auto_block_confidence == 0.8
        assert config.monitor.poll_interval_seconds == 30
        assert config.mcp.port == 9000
        assert config.logging.level == "debug"


# ── Environment Variable Overrides ────────────────────────────


class TestEnvOverrides:
    def test_anthropic_api_key_env(self, tmp_path, monkeypatch):
        """ANTHROPIC_API_KEY env var overrides config file."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-env-test")
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.api_key == "sk-ant-env-test"

    def test_openai_api_key_env(self, tmp_path, monkeypatch):
        """OPENAI_API_KEY env var is used if ANTHROPIC_API_KEY is not set."""
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.setenv("OPENAI_API_KEY", "sk-openai-test")
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.api_key == "sk-openai-test"

    def test_anthropic_takes_precedence(self, tmp_path, monkeypatch):
        """ANTHROPIC_API_KEY takes precedence over OPENAI_API_KEY."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-priority")
        monkeypatch.setenv("OPENAI_API_KEY", "sk-openai-secondary")
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.llm.api_key == "sk-ant-priority"

    def test_mcp_token_env(self, tmp_path, monkeypatch):
        """PIHOLE_MCP_TOKEN env var overrides config file."""
        monkeypatch.setenv("PIHOLE_MCP_TOKEN", "mcp_ph_envtoken")
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        assert config.mcp.auth_token == "mcp_ph_envtoken"

    def test_env_overrides_file_value(self, tmp_path, monkeypatch):
        """Env vars take precedence over file values."""
        config_file = tmp_path / "agent.toml"
        config_file.write_text('[llm]\napi_key = "from-file"\n')
        monkeypatch.setenv("ANTHROPIC_API_KEY", "from-env")
        config = AgentConfig.load(str(config_file))
        assert config.llm.api_key == "from-env"


# ── Safety Dict ───────────────────────────────────────────────


class TestSafetyDict:
    def test_safety_dict_contents(self, tmp_path):
        """safety_dict returns the expected keys."""
        config = AgentConfig.load(str(tmp_path / "nonexistent.toml"))
        d = config.safety_dict()
        assert "blocking_mode" in d
        assert "rate_limit_per_minute" in d
        assert "rate_limit_per_hour" in d
        assert "auto_block_confidence" in d
        assert d["blocking_mode"] == "alert_only"


# ── Dataclass Defaults ────────────────────────────────────────


class TestDataclassDefaults:
    def test_llm_config_defaults(self):
        c = LLMConfig()
        assert c.provider == "anthropic"
        assert c.max_tokens == 4096

    def test_safety_config_defaults(self):
        c = SafetyConfig()
        assert c.blocking_mode == "alert_only"
        assert c.rate_limit_per_minute == 10

    def test_monitor_config_defaults(self):
        c = MonitorConfig()
        assert c.poll_interval_seconds == 60

    def test_mcp_config_defaults(self):
        c = MCPConfig()
        assert c.transport == "stdio"
        assert c.port == 8741

    def test_logging_config_defaults(self):
        c = LoggingConfig()
        assert c.level == "info"
