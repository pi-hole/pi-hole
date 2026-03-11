# Pi-hole AI Agent

AI-powered network analysis and management for Pi-hole. Analyze DNS
traffic, detect anomalies, manage blocking rules, and monitor your
network — from the CLI, Claude Desktop, or your phone.

## Quick Start

### Prerequisites

- Pi-hole v6+ with FTL REST API running
- Python 3.9+
- An Anthropic API key (for Claude-powered analysis)

### Installation

```bash
# Install Python dependencies
pip3 install -r /opt/pihole/pihole_agent/requirements.txt

# Set your API key (choose one method):

# Method 1: Environment variable
export ANTHROPIC_API_KEY="sk-ant-..."

# Method 2: Config file
sudo tee /etc/pihole/agent.toml << 'EOF'
[llm]
provider = "anthropic"
api_key = "sk-ant-..."
EOF
sudo chmod 600 /etc/pihole/agent.toml
```

### Verify Installation

```bash
pihole agent status
```

Expected output:
```
Pi-hole AI Agent Status
========================================
  LLM Provider:     anthropic
  Model:            claude-sonnet-4-20250514
  API Key:          configured
  Blocking Mode:    alert_only
  Rate Limit:       10/min, 100/hr
  MCP Transport:    stdio
  MCP Port:         8741
  MCP Auth Token:   NOT SET
  Audit Log:        /var/log/pihole/agent_audit.log

  Pi-hole API:      connected
```

---

## CLI Usage

### One-Shot Analysis

```bash
# Analyze last 24 hours of DNS traffic
pihole agent analyze

# Analyze last 48 hours
pihole agent analyze --hours 48
```

### Interactive Chat

```bash
# Start a conversation with the network analyzer
pihole agent chat
```

### Real-Time Monitoring

```bash
# Start monitoring in foreground
pihole agent monitor

# Custom poll interval (30 seconds)
pihole agent monitor --interval 30

# Run as background daemon
pihole agent monitor --daemon

# Stop the daemon
pihole agent monitor --stop
```

### Domain Management

```bash
# Block domains via natural language
pihole agent block "block all Facebook tracking domains"
```

### Audit & Rollback

```bash
# View recent agent actions
pihole agent log
pihole agent log --tail 50

# Undo last agent-initiated block
pihole agent rollback

# Undo last 5 blocks
pihole agent rollback 5
```

### Configuration

```bash
# View all config
pihole agent config

# View specific setting
pihole agent config safety.blocking_mode

# Change blocking policy
pihole agent config safety.blocking_mode confirm
```

---

## Claude Desktop Setup (MCP)

The MCP server lets you control Pi-hole directly from Claude Desktop.
**Requires `provider = "anthropic"` in the agent config.**

### Local Pi-hole (same machine as Claude Desktop)

Add to your Claude Desktop config file:

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "pihole": {
      "command": "pihole",
      "args": ["agent", "mcp"]
    }
  }
}
```

Restart Claude Desktop. You should see "Pi-hole Agent" in the MCP
server list.

### Remote Pi-hole (via SSH)

If Pi-hole runs on a different machine (e.g., a Raspberry Pi):

```json
{
  "mcpServers": {
    "pihole": {
      "command": "ssh",
      "args": ["pi@192.168.1.2", "pihole", "agent", "mcp"]
    }
  }
}
```

Make sure SSH key auth is configured (no password prompts).

### What You Can Do in Claude Desktop

**Slash Commands** (type `/` in Claude Desktop):

| Command | Description |
|---------|-------------|
| `/network_health_check` | Full network health audit |
| `/investigate_domain example.com` | Deep investigation of a domain |
| `/block_category "social media trackers"` | Block a category of domains |
| `/traffic_anomaly_report 48` | Anomaly report for last 48 hours |
| `/troubleshoot_blocking example.com` | Debug why a domain is/isn't blocked |

**@Resources** (type `@` to reference live data):

| Resource | Description |
|----------|-------------|
| `@pihole://stats/summary` | Current Pi-hole statistics |
| `@pihole://blocking/status` | Blocking enabled/disabled |
| `@pihole://config/safety` | Safety configuration |
| `@pihole://domains/denied` | All denied domains |
| `@pihole://domains/allowed` | All allowed domains |
| `@pihole://audit/recent` | Recent agent actions |

**Example conversations:**

> "What does my DNS traffic look like today?"
> "Are there any suspicious domains being queried?"
> "Block ads.example.com — it's serving malware"
> "Why isn't tracker.example.com being blocked?"

---

## Claude Mobile Setup

### Step 1: Start the HTTP MCP server

```bash
# Generate an auth token
pihole agent mcp --generate-token

# Start the HTTP server
pihole agent mcp --transport http --port 8741
```

Or run as a systemd service:

```bash
sudo cp /opt/pihole/pihole_agent/../Templates/pihole-agent-mcp.service \
        /etc/systemd/system/
sudo systemctl enable pihole-agent-mcp
sudo systemctl start pihole-agent-mcp
```

### Step 2: Set up HTTPS (required for remote MCP)

With Caddy (easiest — auto-HTTPS):

```
pihole.yourdomain.com {
    reverse_proxy localhost:8741
}
```

With nginx + Let's Encrypt:

```nginx
server {
    listen 443 ssl;
    server_name pihole.yourdomain.com;
    ssl_certificate /etc/letsencrypt/live/pihole.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pihole.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8741;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
    }
}
```

### Step 3: Connect from Claude mobile

In the Claude mobile app: Settings → MCP Servers → Add Remote Server

Enter: `https://pihole.yourdomain.com/`

### LAN-Only Access (no internet exposure)

Use Tailscale or WireGuard instead of exposing to the internet:

```bash
# Start HTTP server listening on all interfaces
pihole agent mcp --transport http --host 0.0.0.0 --port 8741
```

Connect via your VPN's internal IP from the mobile app.

---

## Configuration Reference

Config file: `/etc/pihole/agent.toml`

```toml
[llm]
provider = "anthropic"              # "anthropic" or "openai"
api_key = ""                        # Or use ANTHROPIC_API_KEY env var
model = "claude-sonnet-4-20250514"  # Model to use for analysis
base_url = ""                       # For OpenAI-compatible endpoints
max_tokens = 4096

[safety]
blocking_mode = "alert_only"        # See "Blocking Modes" below
protected_domains_file = "/etc/pihole/agent_protected_domains.list"
rate_limit_per_minute = 10
rate_limit_per_hour = 100
auto_block_confidence = 0.95

[monitor]
poll_interval_seconds = 60
analysis_window_minutes = 15
alert_log = "/var/log/pihole/agent_alerts.log"
state_file = "/etc/pihole/agent_monitor_state.json"

[mcp]
enabled = true
transport = "stdio"                 # "stdio" or "http"
port = 8741
host = "127.0.0.1"                  # "0.0.0.0" for all interfaces
auth_token = ""                     # Required for HTTP; generate with --generate-token

[logging]
audit_log = "/var/log/pihole/agent_audit.log"
level = "info"
```

### Blocking Modes

| Mode | Behavior |
|------|----------|
| `alert_only` | Detect anomalies, never block. Default and safest. |
| `confirm` | Prompt for confirmation before each block (interactive only). |
| `auto_high_confidence` | Auto-block above confidence threshold (0.95). Alert the rest. |
| `auto_all` | Block everything the agent flags. Maximum automation, maximum risk. |

Change at any time:

```bash
pihole agent config safety.blocking_mode confirm
```

### Protected Domains

Domains in `/etc/pihole/agent_protected_domains.list` can never be
blocked by agents, regardless of mode. Add one domain per line:

```
# DNS resolvers
dns.google
cloudflare-dns.com

# My critical services
mycompany.com
vpn.mycompany.com
```

A default set is always applied (DNS resolvers, OS update servers,
GitHub, Pi-hole itself).

---

## Safety

### Guardrails

Every agent action passes through safety checks:

1. **Domain protection** — protected domains cannot be blocked
2. **Rate limiting** — max 10 blocks/min, 100/hr (configurable)
3. **Policy check** — action must be allowed by the blocking mode
4. **Audit logging** — every action recorded with timestamp, rationale

### Audit Log

All agent actions are logged to `/var/log/pihole/agent_audit.log`:

```json
{"timestamp": "2026-03-11T14:23:01Z", "source": "mcp", "agent": "claude",
 "action": "block_domain", "target": "suspicious.example.com",
 "rationale": "DGA pattern", "status": "OK"}
```

View with:

```bash
pihole agent log
```

### Rollback

Undo agent-initiated blocks:

```bash
pihole agent rollback      # undo last block
pihole agent rollback 5    # undo last 5 blocks
```

---

## Development

### Running Tests

```bash
# Install test dependencies
pip install -r test/requirements.txt

# Run agent unit tests (no Docker, no Pi-hole required)
pytest test/test_agent_*.py -v

# Run with coverage
pytest test/test_agent_*.py -v --cov=advanced/Scripts/pihole_agent
```

### Project Structure

```
advanced/Scripts/pihole_agent/
├── __init__.py
├── __main__.py           # CLI entry point
├── config.py             # Configuration management
├── api_client.py         # FTL REST API client
├── db_reader.py          # Read-only SQLite access
├── requirements.txt      # Python dependencies
├── core/
│   ├── safety.py         # Safety guardrails
│   ├── base_agent.py     # Base agent class (Phase 2)
│   ├── tool_registry.py  # Tool registration (Phase 2)
│   └── session.py        # Session management (Phase 2)
├── tools/
│   ├── blocking.py       # Block/unblock tools (Phase 3)
│   ├── query_tools.py    # Query tools (Phase 2)
│   └── analysis_tools.py # Analysis tools (Phase 2)
├── agents/
│   ├── network_analyzer.py   # (Phase 3)
│   ├── access_controller.py  # (Phase 3)
│   └── traffic_monitor.py    # (Phase 4)
├── monitor/
│   ├── poller.py         # Query log poller (Phase 4)
│   └── alerting.py       # Alert generation (Phase 4)
├── mcp/
│   ├── server.py         # MCP server (Claude-only)
│   └── auth.py           # HTTP transport auth
└── templates/
    └── system_prompts.py # Agent system prompts (Phase 3)
```
