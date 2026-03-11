"""Authentication middleware for MCP HTTP transport.

Validates bearer tokens on incoming HTTP requests. Only applies to the
HTTP transport — stdio transport (Claude Desktop) is inherently authenticated
by being a local subprocess.
"""

import hmac
import secrets
from pathlib import Path

from pihole_agent.config import AgentConfig


class MCPAuthError(Exception):
    """Raised when authentication fails."""

    pass


def validate_token(provided_token: str) -> bool:
    """Validate a provided bearer token against the configured auth token."""
    config = AgentConfig.load()
    expected = config.mcp.auth_token
    if not expected:
        return False
    return hmac.compare_digest(provided_token, expected)


def generate_token() -> str:
    """Generate a new secure auth token."""
    return f"mcp_ph_{secrets.token_hex(32)}"


def save_token_to_config(
    token: str, config_path: str = "/etc/pihole/agent.toml"
) -> None:
    """Save a generated token to the config file.

    Creates the file if it doesn't exist, or updates the auth_token line
    if it does.
    """
    path = Path(config_path)

    if path.exists():
        content = path.read_text()
        if "auth_token" in content:
            lines = content.splitlines()
            new_lines = []
            for line in lines:
                if line.strip().startswith("auth_token"):
                    new_lines.append(f'auth_token = "{token}"')
                else:
                    new_lines.append(line)
            path.write_text("\n".join(new_lines) + "\n")
        else:
            # Add under [mcp] section if it exists, else append
            if "[mcp]" in content:
                content = content.replace("[mcp]", f'[mcp]\nauth_token = "{token}"')
                path.write_text(content)
            else:
                with open(path, "a") as f:
                    f.write(f'\n[mcp]\nauth_token = "{token}"\n')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'[mcp]\nauth_token = "{token}"\n')
        path.chmod(0o600)

    print(f"Generated MCP auth token: {token}")
    print(f"Token saved to {config_path}")
