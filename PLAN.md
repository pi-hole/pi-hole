# Pi-hole AI Agent Integration Plan

## 1. Architecture Overview

This plan introduces a Python-based AI agent layer that sits alongside Pi-hole's existing bash CLI. Agents interact with Pi-hole exclusively through the FTL REST API (for mutations) and read-only SQLite database access (for analysis), preserving the existing architecture completely.

```
User
  │
  ▼
pihole agent <command>           (bash CLI entry point)
  │
  ▼
advanced/Scripts/piholeAgent.sh  (bash shim: validates env, execs Python)
  │
  ▼
advanced/Scripts/pihole_agent/   (Python package)
  ├── __main__.py                (CLI argument parsing, dispatch)
  ├── config.py                  (configuration management)
  ├── llm/                       (provider-agnostic LLM abstraction)
  │   ├── base.py                (abstract LLM interface)
  │   ├── anthropic_provider.py  (Claude implementation)
  │   └── openai_provider.py     (OpenAI-compatible implementation)
  ├── api_client.py              (Python port of api.sh — FTL API client)
  ├── db_reader.py               (read-only SQLite: pihole-FTL.db, gravity.db)
  ├── core/                      (framework internals)
  │   ├── base_agent.py          (abstract agent with tool-use loop)
  │   ├── tool_registry.py       (tool registration and dispatch)
  │   ├── safety.py              (guardrails: protection, rate limits, audit)
  │   └── session.py             (conversation session management)
  ├── tools/                     (Pi-hole operations as agent tools)
  │   ├── blocking.py            (block/unblock domains, enable/disable)
  │   ├── query_tools.py         (query logs, search adlists, stats)
  │   └── analysis_tools.py      (anomaly detection, DGA, traffic summary)
  ├── agents/                    (agent implementations)
  │   ├── network_analyzer.py    (DNS traffic analysis)
  │   ├── access_controller.py   (blocking rule management)
  │   └── traffic_monitor.py     (long-running real-time monitoring)
  ├── monitor/                   (extended ingestion subsystem)
  │   ├── poller.py              (periodic query log poller)
  │   └── alerting.py            (alert generation and routing)
  └── templates/
      └── system_prompts.py      (system prompts for each agent type)
```

### Key Architectural Decisions

**Python as the agent runtime.** Pi-hole's test suite already uses Python. Python provides access to AI SDKs, sqlite3, and async I/O needed for agent work. A thin bash shim (`piholeAgent.sh`) bridges the existing `pihole` CLI dispatch pattern.

**Provider-agnostic LLM layer.** The agent framework abstracts the AI model behind a common interface. Users can choose between Anthropic Claude, OpenAI-compatible APIs, or local models (e.g., via Ollama). Swappable via configuration — no code changes needed.

**API-first integration.** All mutating operations (blocking, unblocking, enable/disable) go through FTL's REST API, mirroring the patterns in `api.sh`, `list.sh`, and `query.sh`. No direct database writes, ever.

**Read-only database access for analysis.** Agents query `pihole-FTL.db` (query logs) and `gravity.db` (blocklists) via read-only SQLite connections (`?mode=ro`). FTL already uses WAL mode, so concurrent reads are safe.

**Tool-use pattern.** Pi-hole operations are registered as tools with JSON schemas. The LLM reasons about user requests and calls tools as needed. Adding a new capability = registering a new tool. This is the primary extensibility mechanism.

---

## 2. CLI Integration

### 2.1 New `pihole agent` subcommand

**Modify:** `/home/user/pi-hole/pihole`

Add to the non-root command dispatch block (around line 548-563):
```bash
"agent" ) agentFunc "$@";;
```

Add function (following the pattern of `queryFunc` at line 137):
```bash
agentFunc() {
  shift
  "${PI_HOLE_SCRIPT_DIR}"/piholeAgent.sh "$@"
  exit 0
}
```

Add help text to `helpFunc` (around line 510):
```
  agent               AI-powered network analysis and management
                        Add '-h' for more info on agent usage
```

### 2.2 Bash shim: `piholeAgent.sh`

**Create:** `/home/user/pi-hole/advanced/Scripts/piholeAgent.sh`

Follows the pattern of `query.sh` — validates Python availability and delegates:

```bash
#!/usr/bin/env bash
# Pi-hole AI Agent - delegates to Python agent framework
PI_HOLE_SCRIPT_DIR="/opt/pihole"
AGENT_DIR="${PI_HOLE_SCRIPT_DIR}/pihole_agent"

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required for agent functionality"
    echo "Install with: sudo apt-get install python3"
    exit 1
fi

# Check minimum Python version (3.9+)
if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" 2>/dev/null; then
    echo "Error: Python 3.9 or later is required"
    exit 1
fi

PYTHONPATH="${PI_HOLE_SCRIPT_DIR}" exec python3 -m pihole_agent "$@"
```

### 2.3 User-facing commands

```
pihole agent analyze [--hours N]      One-shot analysis of recent DNS traffic
pihole agent chat                     Interactive conversation with the agent
pihole agent monitor [--daemon]       Start real-time traffic monitoring
pihole agent monitor --stop           Stop monitoring daemon
pihole agent status                   Show agent config, recent findings
pihole agent rollback [N]             Undo last N agent-initiated blocks
pihole agent config [key] [value]     View/set agent configuration
pihole agent log [--tail N]           View agent audit log
pihole agent --help                   Show help text
```

---

## 3. Component Design

### 3.1 Provider-Agnostic LLM Layer (`llm/`)

**`llm/base.py`** — Abstract interface:
```python
class LLMProvider(ABC):
    @abstractmethod
    def create_message(self, system: str, messages: list[dict],
                       tools: list[dict], max_tokens: int) -> LLMResponse: ...

class LLMResponse:
    content: list[ContentBlock]  # text or tool_use blocks
    stop_reason: str             # "end_turn" or "tool_use"
```

**`llm/anthropic_provider.py`** — Claude implementation using the Anthropic SDK. Supports Claude's native tool-use format.

**`llm/openai_provider.py`** — OpenAI-compatible implementation. Works with OpenAI, Azure OpenAI, Ollama, LM Studio, vLLM, or any OpenAI-compatible API. Tool schemas are translated to OpenAI's function-calling format.

Configuration selects the provider:
```toml
[llm]
provider = "anthropic"           # or "openai"
api_key = ""                     # or use env var
model = "claude-sonnet-4-20250514"
base_url = ""                    # for OpenAI-compatible endpoints (Ollama, etc.)
```

### 3.2 FTL API Client (`api_client.py`)

Direct Python port of the authentication and request pattern from `advanced/Scripts/api.sh`. Key functions ported:

| Bash function (api.sh) | Python method |
|------------------------|---------------|
| `TestAPIAvailability()` | `discover_api()` — DNS CHAOS query to find API URL |
| `LoginAPI()` | `login()` — authenticate via POST /api/auth, get SID |
| `GetFTLData()` | `get(endpoint)` — HTTP GET with SID header |
| `PostFTLData()` | `post(endpoint, data)` — HTTP POST with SID header |
| `LogoutAPI()` | `logout()` — DELETE /api/auth |

Implements context manager for automatic session cleanup:
```python
with PiholeAPIClient() as client:
    stats = client.get("stats/summary")
    client.post("domains/deny/exact", {"domain": "bad.example.com"})
```

### 3.3 Database Reader (`db_reader.py`)

Read-only SQLite access to both Pi-hole databases. Database paths are resolved the same way `list.sh` does — via `pihole-FTL --config -q files.database` and `pihole-FTL --config -q files.gravity`.

```python
class PiholeDBReader:
    def get_recent_queries(self, hours: int = 24, limit: int = 10000) -> list[dict]
    def get_query_counts_by_domain(self, hours: int = 24) -> list[dict]
    def get_query_counts_by_client(self, hours: int = 24) -> list[dict]
    def get_blocked_domains(self) -> list[str]
    def get_domainlist(self, type_id: int) -> list[dict]
```

All connections use `sqlite3.connect("file:...?mode=ro", uri=True)`.

### 3.4 Tool Registry (`core/tool_registry.py`)

Tools are Python functions decorated with metadata. The registry:

1. Stores tool functions with their JSON schemas
2. Translates schemas to the active LLM provider's format
3. Dispatches tool calls through the safety layer
4. Returns results as strings for the LLM

```python
@tool(
    name="block_domain",
    description="Add a domain to Pi-hole's deny list",
    requires_confirmation=True,
    rate_limited=True
)
def block_domain(domain: str, comment: str = "") -> str:
    ...
```

New tools can be registered by:
1. Writing a decorated function in `tools/`
2. Importing it in the appropriate agent's setup

### 3.5 Safety & Guardrails (`core/safety.py`)

The most critical component. Enforces multiple layers of protection:

**Domain protection list.** A configurable set of domains that can never be blocked (OS update servers, DNS resolvers, auth providers, the Pi-hole admin interface). Default list plus user additions in `/etc/pihole/agent_protected_domains.list`.

**Configurable blocking policy.** Users choose their comfort level at any time via `pihole agent config`:

| Mode | Behavior | Default |
|------|----------|---------|
| `alert_only` | Detect and log anomalies. Never block automatically. | Yes (default) |
| `confirm` | Prompt user for y/n before each blocking action (interactive sessions) | — |
| `auto_high_confidence` | Auto-block domains exceeding a configurable confidence threshold (e.g., confirmed DGA, known malware C2). Alert for everything else. | — |
| `auto_all` | Block any domain the agent deems suspicious. Maximum automation, maximum risk. | — |

The mode can be changed at any time:
```bash
pihole agent config safety.blocking_mode alert_only
pihole agent config safety.blocking_mode auto_high_confidence
```

**Rate limiting.** Maximum N blocking actions per time window (default: 10/minute, 100/hour). Prevents runaway agent behavior regardless of mode.

**Audit logging.** Every agent action is logged to `/var/log/pihole/agent_audit.log`:
```
2026-03-11T14:23:01Z | NetworkAnalyzer | block_domain | suspicious.example.com | "DGA pattern detected, entropy=4.8" | CONFIRMED
```

**Rollback.** Before any blocking action, state is checkpointed. `pihole agent rollback [N]` undoes the last N agent-initiated blocks by calling the appropriate unblock API endpoints.

```python
class SafetyGuard:
    def check_domain_protection(self, domain: str) -> bool
    def check_rate_limit(self, action_type: str) -> bool
    def check_blocking_policy(self, action: str, confidence: float) -> PolicyDecision
    def request_confirmation(self, action: str, details: dict) -> bool
    def log_action(self, agent: str, action: str, target: str, rationale: str)
    def rollback(self, n: int = 1)
```

---

## 4. Tool Definitions

### 4.1 Blocking Tools (`tools/blocking.py`)

| Tool | FTL API Endpoint | Safety Level |
|------|-----------------|-------------|
| `block_domain` | POST `/api/domains/deny/exact` | Confirmation + rate limit |
| `unblock_domain` | POST `/api/domains:batchDelete` | Confirmation |
| `block_regex` | POST `/api/domains/deny/regex` | Confirmation + rate limit |
| `enable_blocking` | POST `/api/dns/blocking` `{blocking: true}` | Logged |
| `disable_blocking` | POST `/api/dns/blocking` `{blocking: false, timer: N}` | Confirmation |
| `list_denied_domains` | GET `/api/domains/deny/exact` | Read-only |
| `list_allowed_domains` | GET `/api/domains/allow/exact` | Read-only |

### 4.2 Query & Search Tools (`tools/query_tools.py`)

| Tool | Source | Safety |
|------|--------|--------|
| `search_adlists` | GET `/api/search/{domain}` | Read-only |
| `get_stats_summary` | GET `/api/stats/summary` | Read-only |
| `get_recent_queries` | SQLite `pihole-FTL.db` | Read-only |
| `get_top_domains` | SQLite `pihole-FTL.db` | Read-only |
| `get_top_clients` | SQLite `pihole-FTL.db` | Read-only |
| `get_domain_list` | GET `/api/domains/{type}/{kind}` | Read-only |

### 4.3 Analysis Tools (`tools/analysis_tools.py`)

| Tool | Description |
|------|-------------|
| `detect_anomalous_domains` | Statistical analysis: flag domains with unusual query volume or timing |
| `detect_dga_domains` | Heuristic detection of algorithmically generated domain names (entropy-based) |
| `analyze_query_trend` | Time-series analysis of query volume for spike detection |
| `classify_domain_risk` | Score domain risk based on TLD, entropy, query pattern |
| `summarize_traffic` | Aggregate statistics over a time window for reporting |

These are pure Python computations — no external API calls, no LLM calls. They provide structured data for the agent to reason about.

---

## 5. Agent Types

### 5.1 NetworkAnalyzer (`agents/network_analyzer.py`)

**Purpose:** On-demand analysis of DNS traffic patterns.

**System prompt:** Instructs the model to act as a network security analyst examining DNS traffic. Analyze patterns, identify anomalies, explain findings clearly. Flag suspicious domains with reasoning before recommending action.

**Tools:** All query tools + all analysis tools. Can recommend blocking but delegates to AccessController for execution.

**Usage:** `pihole agent analyze` (one-shot report) or `pihole agent chat` (interactive).

### 5.2 AccessController (`agents/access_controller.py`)

**Purpose:** Natural-language interface for managing blocking rules.

**System prompt:** Help manage DNS blocking rules via conversation. Always explain the impact of changes. Respect the configured blocking policy.

**Tools:** All blocking tools + query tools (for verification).

**Usage:** Invoked within `pihole agent chat` when intent is access control, or directly via `pihole agent block "block facebook tracking domains"`.

### 5.3 TrafficMonitor (`agents/traffic_monitor.py`)

**Purpose:** Long-running background monitoring with alerting.

**Architecture:**
- Runs as foreground process or daemon via `pihole agent monitor [--daemon]`
- PID file at `/run/pihole-agent-monitor.pid`
- Polls `pihole-FTL.db` every configurable interval (default: 60s)
- Maintains sliding window of query statistics in memory
- Periodically sends summary to LLM for anomaly classification
- Writes alerts to `/var/log/pihole/agent_alerts.log`
- Respects the configured blocking policy for auto-blocking decisions

---

## 6. Data Pipeline for Extended Ingestion

### 6.1 Polling Architecture (`monitor/poller.py`)

1. Read last-processed query ID from state file (`/etc/pihole/agent_monitor_state.json`)
2. Query `pihole-FTL.db` for new rows since that ID
3. Batch queries into configurable time windows (default: 15 minutes)
4. Run analysis tools on each batch
5. If anomalies exceed threshold, send summary to LLM for classification
6. Write alerts and optionally trigger blocking (per policy)
7. Update state file

**Why database polling, not log tailing:**
- Structured data (client IP, query type, status, timestamp) — no regex parsing
- Survives log rotations
- Read-only SQLite with WAL mode = no race conditions
- Natural checkpoint/resume on restart

### 6.2 Alert System (`monitor/alerting.py`)

Alerts are structured JSON written to the alert log:
```json
{
  "timestamp": "2026-03-11T14:23:01Z",
  "severity": "high",
  "type": "dga_detection",
  "domains": ["asd8f7g9h.example.com"],
  "client": "192.168.1.42",
  "confidence": 0.97,
  "action_taken": "blocked",
  "rationale": "Domain exhibits DGA characteristics: high entropy (4.8), random consonant clusters"
}
```

Future extension point: alerting module can support webhooks, email, Slack notifications by adding output handlers.

---

## 7. Configuration

**File:** `/etc/pihole/agent.toml`

```toml
[llm]
provider = "anthropic"              # "anthropic", "openai", or "openai" with custom base_url
api_key = ""                        # Or use ANTHROPIC_API_KEY / OPENAI_API_KEY env vars
model = "claude-sonnet-4-20250514"
base_url = ""                       # For Ollama/LM Studio: "http://localhost:11434/v1"
max_tokens = 4096

[safety]
blocking_mode = "alert_only"        # "alert_only", "confirm", "auto_high_confidence", "auto_all"
protected_domains_file = "/etc/pihole/agent_protected_domains.list"
rate_limit_per_minute = 10
rate_limit_per_hour = 100
auto_block_confidence = 0.95        # Threshold for auto_high_confidence mode

[monitor]
poll_interval_seconds = 60
analysis_window_minutes = 15
alert_log = "/var/log/pihole/agent_alerts.log"
state_file = "/etc/pihole/agent_monitor_state.json"

[mcp]
enabled = true
transport = "stdio"                 # "stdio" for Claude Desktop, "http" for mobile/remote
port = 8741                         # Port for HTTP transport
host = "127.0.0.1"                  # Bind address ("0.0.0.0" for all interfaces)
auth_token = ""                     # Required for HTTP transport; generate via --generate-token

[logging]
audit_log = "/var/log/pihole/agent_audit.log"
level = "info"                      # "debug", "info", "warning", "error"
```

File permissions: `0600`, readable only by root/pihole user (protects API keys).

---

## 8. Implementation Phases

### Phase 1: Foundation
**Goal:** CLI integration, API client, database reader

**Create:**
- `advanced/Scripts/pihole_agent/__init__.py`
- `advanced/Scripts/pihole_agent/__main__.py`
- `advanced/Scripts/pihole_agent/config.py`
- `advanced/Scripts/pihole_agent/api_client.py`
- `advanced/Scripts/pihole_agent/db_reader.py`
- `advanced/Scripts/piholeAgent.sh`
- `requirements-agent.txt`

**Modify:**
- `pihole` — add `agent` case + `agentFunc`
- `advanced/bash-completion/pihole.bash` — add `agent` completion

**Validation:** `pihole agent status` connects to FTL API and reports database stats.

### Phase 2: LLM Layer + Core Framework
**Goal:** Provider-agnostic LLM, tool registry, safety guardrails

**Create:**
- `advanced/Scripts/pihole_agent/llm/__init__.py`
- `advanced/Scripts/pihole_agent/llm/base.py`
- `advanced/Scripts/pihole_agent/llm/anthropic_provider.py`
- `advanced/Scripts/pihole_agent/llm/openai_provider.py`
- `advanced/Scripts/pihole_agent/core/__init__.py`
- `advanced/Scripts/pihole_agent/core/base_agent.py`
- `advanced/Scripts/pihole_agent/core/tool_registry.py`
- `advanced/Scripts/pihole_agent/core/safety.py`
- `advanced/Scripts/pihole_agent/core/session.py`
- `advanced/Scripts/pihole_agent/tools/__init__.py`
- `advanced/Scripts/pihole_agent/tools/query_tools.py`
- `advanced/Scripts/pihole_agent/tools/analysis_tools.py`

**Validation:** Tools execute individually; safety guard blocks protected domains.

### Phase 3: Interactive Agents
**Goal:** NetworkAnalyzer and AccessController agents

**Create:**
- `advanced/Scripts/pihole_agent/agents/__init__.py`
- `advanced/Scripts/pihole_agent/agents/network_analyzer.py`
- `advanced/Scripts/pihole_agent/agents/access_controller.py`
- `advanced/Scripts/pihole_agent/tools/blocking.py`
- `advanced/Scripts/pihole_agent/templates/__init__.py`
- `advanced/Scripts/pihole_agent/templates/system_prompts.py`

**Validation:** `pihole agent analyze` produces a traffic report. `pihole agent chat` supports interactive Q&A and domain management.

### Phase 4: Traffic Monitor
**Goal:** Long-running monitoring daemon with alerting

**Create:**
- `advanced/Scripts/pihole_agent/agents/traffic_monitor.py`
- `advanced/Scripts/pihole_agent/monitor/__init__.py`
- `advanced/Scripts/pihole_agent/monitor/poller.py`
- `advanced/Scripts/pihole_agent/monitor/alerting.py`
- `advanced/Templates/pihole-agent-monitor.service` (systemd unit)

**Validation:** `pihole agent monitor` runs, detects anomalous queries, writes alerts.

### Phase 5: MCP Server (Claude Desktop & Mobile)
**Goal:** Expose all agent tools via MCP for Claude Desktop and mobile control

**Create:**
- `advanced/Scripts/pihole_agent/mcp_server.py`
- `advanced/Scripts/pihole_agent/mcp_auth.py`
- `advanced/Scripts/pihole_agent/mcp_resources.py`
- `advanced/Scripts/piholeAgentMCP.sh`
- `advanced/Templates/pihole-agent-mcp.service`

**Modify:**
- `advanced/Scripts/pihole_agent/__main__.py` — add `mcp` subcommand
- `requirements-agent.txt` — add `mcp[cli]>=1.0.0`

**Validation:**
- `pihole agent mcp` starts stdio server; Claude Desktop discovers and uses tools
- `pihole agent mcp --transport http` starts HTTP server; Claude mobile connects
- Safety guardrails apply to all MCP tool calls
- Audit log records MCP-sourced actions

### Phase 6: Testing
**Goal:** Unit tests for safety-critical components

**Create:**
- `test/test_agent_safety.py`
- `test/test_agent_tools.py`
- `test/test_agent_api_client.py`
- `test/test_agent_mcp.py`

---

## 9. MCP Server — Claude Desktop & Mobile Control

The Pi-hole agent framework exposes its full toolset as an **MCP (Model Context Protocol) server**, enabling control from Claude Desktop, Claude mobile apps, and any MCP-compatible client. This turns your Pi-hole into a tool that Claude can use directly — no CLI needed.

### 9.1 Architecture

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Claude Desktop     │     │  Claude Mobile /      │     │  Any MCP Client │
│  (stdio transport)  │     │  Remote Clients       │     │  (custom apps)  │
└────────┬────────────┘     │  (HTTP transport)     │     └────────┬────────┘
         │                  └──────────┬─────────────┘              │
         │ stdin/stdout                │ HTTPS                      │
         │                             │                            │
         ▼                             ▼                            │
┌─────────────────────────────────────────────────────────────────────┐
│                    Pi-hole MCP Server                                │
│  advanced/Scripts/pihole_agent/mcp_server.py                        │
│                                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │
│  │ MCP Tools   │  │ MCP Resources│  │ Safety Layer (same guards) │ │
│  │ (14 tools)  │  │ (live data)  │  │ rate limits, protection    │ │
│  └─────────────┘  └──────────────┘  └────────────────────────────┘ │
│                           │                                         │
│              ┌────────────┼────────────┐                            │
│              ▼            ▼            ▼                            │
│      FTL REST API    pihole-FTL.db   gravity.db                    │
│      (mutations)     (read-only)     (read-only)                   │
└─────────────────────────────────────────────────────────────────────┘
```

The MCP server reuses the same `api_client.py`, `db_reader.py`, `tools/`, and `core/safety.py` modules that the CLI agents use. No logic duplication — the MCP layer is purely a protocol adapter.

### 9.2 New Files

```
advanced/Scripts/pihole_agent/
  ├── mcp_server.py              # MCP server: tool + resource registration
  ├── mcp_auth.py                # Authentication middleware for remote access
  └── mcp_resources.py           # MCP resource definitions (live data endpoints)
```

Plus setup/config files:
```
advanced/Scripts/piholeAgentMCP.sh          # Bash shim for MCP server startup
advanced/Templates/pihole-agent-mcp.service # systemd unit for HTTP transport
```

### 9.3 MCP Server Implementation (`mcp_server.py`)

Built with the official MCP Python SDK (`mcp` package) using FastMCP:

```python
from mcp.server.fastmcp import FastMCP, Context

mcp = FastMCP("Pi-hole Agent")

# ── MCP Tools (mapped 1:1 from existing tools/) ──────────────

@mcp.tool()
def get_stats_summary() -> dict:
    """Get Pi-hole statistics: total queries, blocked, percentage, top domains."""
    with PiholeAPIClient() as client:
        return client.get("stats/summary")

@mcp.tool()
def get_recent_queries(hours: int = 24, limit: int = 100) -> list[dict]:
    """Get recent DNS queries from the Pi-hole query log."""
    reader = PiholeDBReader()
    return reader.get_recent_queries(hours=hours, limit=limit)

@mcp.tool()
def block_domain(domain: str, comment: str = "") -> dict:
    """Add a domain to Pi-hole's deny list. Requires safety check."""
    safety = SafetyGuard.from_config()
    safety.check_domain_protection(domain)  # raises if protected
    safety.check_rate_limit("block")        # raises if exceeded
    with PiholeAPIClient() as client:
        result = client.post("domains/deny/exact", {"domain": domain, "comment": comment})
    safety.log_action("mcp", "block_domain", domain, comment)
    return result

@mcp.tool()
def unblock_domain(domain: str) -> dict:
    """Remove a domain from Pi-hole's deny list."""
    # ... similar pattern with safety checks

@mcp.tool()
def search_adlists(domain: str, partial: bool = True) -> dict:
    """Search Pi-hole's adlists for a domain."""
    with PiholeAPIClient() as client:
        return client.get(f"search/{domain}?N=20&partial={str(partial).lower()}")

@mcp.tool()
def enable_blocking() -> dict:
    """Enable Pi-hole DNS blocking."""
    with PiholeAPIClient() as client:
        return client.post("dns/blocking", {"blocking": True})

@mcp.tool()
def disable_blocking(seconds: int = 0) -> dict:
    """Temporarily disable Pi-hole DNS blocking. seconds=0 means indefinite."""
    safety = SafetyGuard.from_config()
    safety.check_rate_limit("disable_blocking")
    with PiholeAPIClient() as client:
        data = {"blocking": False}
        if seconds > 0:
            data["timer"] = seconds
        return client.post("dns/blocking", data)

@mcp.tool()
def get_top_domains(count: int = 10, hours: int = 24) -> list[dict]:
    """Get top queried domains over the specified time period."""
    reader = PiholeDBReader()
    return reader.get_query_counts_by_domain(hours=hours)[:count]

@mcp.tool()
def get_top_clients(count: int = 10, hours: int = 24) -> list[dict]:
    """Get top DNS clients over the specified time period."""
    reader = PiholeDBReader()
    return reader.get_query_counts_by_client(hours=hours)[:count]

@mcp.tool()
def detect_anomalous_domains(hours: int = 24) -> list[dict]:
    """Detect domains with anomalous query patterns (potential DGA, tunneling)."""
    # Uses analysis_tools.py internally

@mcp.tool()
def analyze_query_trend(hours: int = 24, bucket_minutes: int = 60) -> list[dict]:
    """Get query volume trend over time, bucketed by interval."""
    # Time-series data for the LLM to reason about

@mcp.tool()
def list_denied_domains() -> list[dict]:
    """List all domains currently on the deny list."""
    with PiholeAPIClient() as client:
        return client.get("domains/deny/exact")

@mcp.tool()
def list_allowed_domains() -> list[dict]:
    """List all domains currently on the allow list."""
    with PiholeAPIClient() as client:
        return client.get("domains/allow/exact")

@mcp.tool()
def get_audit_log(last_n: int = 20) -> list[dict]:
    """Get the last N entries from the agent audit log."""
    # Reads /var/log/pihole/agent_audit.log

# ── MCP Resources (live data endpoints) ──────────────

@mcp.resource("pihole://stats/summary")
def stats_summary() -> str:
    """Current Pi-hole statistics summary."""
    with PiholeAPIClient() as client:
        return json.dumps(client.get("stats/summary"), indent=2)

@mcp.resource("pihole://blocking/status")
def blocking_status() -> str:
    """Current DNS blocking status (enabled/disabled)."""
    with PiholeAPIClient() as client:
        return json.dumps(client.get("dns/blocking"))

@mcp.resource("pihole://config/safety")
def safety_config() -> str:
    """Current agent safety configuration."""
    config = AgentConfig.load()
    return json.dumps(config.safety_dict(), indent=2)
```

### 9.4 Transport Modes

The MCP server supports two transport modes, selectable at startup:

**stdio (for Claude Desktop):**
```bash
pihole agent mcp                      # starts in stdio mode (default)
pihole agent mcp --transport stdio    # explicit
```

Claude Desktop launches this as a subprocess. Configure in `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "pihole": {
      "command": "pihole",
      "args": ["agent", "mcp"],
      "env": {}
    }
  }
}
```

If Pi-hole is on a remote machine and you SSH in:
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

**Streamable HTTP (for mobile and remote clients):**
```bash
pihole agent mcp --transport http --port 8741
pihole agent mcp --transport http --port 8741 --host 0.0.0.0  # listen on all interfaces
```

This starts a persistent HTTP server that Claude mobile apps (and any MCP client) can connect to.

### 9.5 Mobile Access Setup

Claude for iOS and Android support remote MCP servers. To control Pi-hole from your phone:

**Step 1: Start the MCP HTTP server on your Pi-hole:**
```bash
# One-time: start as a systemd service
sudo systemctl enable pihole-agent-mcp
sudo systemctl start pihole-agent-mcp
```

The systemd unit (`advanced/Templates/pihole-agent-mcp.service`) runs:
```
pihole agent mcp --transport http --port 8741 --host 127.0.0.1
```

**Step 2: Set up a reverse proxy with HTTPS (required for remote MCP).**

Example with Caddy (auto-HTTPS):
```
pihole.yourdomain.com {
    reverse_proxy localhost:8741
}
```

Or with nginx + Let's Encrypt:
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
        proxy_buffering off;          # required for SSE streams
    }
}
```

**Step 3: Add the remote server in Claude mobile app:**

Go to Settings → MCP Servers → Add Remote Server, enter:
```
https://pihole.yourdomain.com/
```

**For LAN-only access (no internet exposure):** Use Tailscale or WireGuard to create a secure tunnel. The MCP server binds to `0.0.0.0` and your VPN handles authentication and encryption.

### 9.6 MCP Authentication (`mcp_auth.py`)

The HTTP transport needs its own authentication layer (separate from FTL API auth, which is handled internally):

**Token-based auth.** A bearer token is configured in `agent.toml` and required in the `Authorization` header for all HTTP transport requests:

```toml
[mcp]
enabled = true
transport = "http"                  # "stdio" or "http"
port = 8741
host = "127.0.0.1"                  # "0.0.0.0" to listen on all interfaces
auth_token = ""                     # Required for HTTP transport. Generate with: pihole agent mcp --generate-token
```

Generate a secure token:
```bash
$ pihole agent mcp --generate-token
Generated MCP auth token: mcp_ph_a7b3c9d2e1f0...
Token saved to /etc/pihole/agent.toml
```

### 9.7 Safety in MCP Context

The same `SafetyGuard` from `core/safety.py` protects all MCP tool calls. However, MCP has an important difference from CLI usage: **there is no interactive confirmation prompt.** The MCP client (Claude Desktop/Mobile) decides whether to show the user a confirmation dialog based on the tool's metadata.

To handle this:
- All mutating MCP tools include `"confirmation": true` in their annotations
- The MCP server sets `blocking_mode` to `alert_only` by default for MCP connections
- Users can escalate to `auto_high_confidence` via the config
- Rate limiting and domain protection apply regardless
- Every MCP tool call is audit-logged with `source: "mcp"` to distinguish from CLI actions

### 9.8 CLI Commands for MCP

```
pihole agent mcp                          # Start MCP server (stdio, for Claude Desktop)
pihole agent mcp --transport http         # Start MCP server (HTTP, for mobile/remote)
pihole agent mcp --port 8741             # Custom port (default: 8741)
pihole agent mcp --generate-token        # Generate auth token for HTTP transport
pihole agent mcp --status                # Show MCP server status
```

---

## 10. Extensibility Path (updated)

### Adding a new tool
1. Write a decorated function in `tools/`
2. Import it in the appropriate agent's setup method
3. Done — the tool registry handles schema generation and dispatch

### Adding a new agent type
1. Subclass `BaseAgent` in `agents/`
2. Set its `system_prompt` and register its tools
3. Add a CLI subcommand in `__main__.py`

### Adding a new LLM provider
1. Subclass `LLMProvider` in `llm/`
2. Implement `create_message()` with the provider's API
3. Register the provider name in `config.py`

### Adding a new MCP tool
1. Write the tool function in `tools/` (same as for CLI agents)
2. Add an `@mcp.tool()` wrapper in `mcp_server.py` that calls it
3. The MCP SDK auto-generates the JSON schema from type hints

### Future agent ideas (non-exhaustive)
- **ThreatIntelAgent** — integrates with threat intelligence feeds to proactively block known-bad domains
- **ClientProfiler** — builds behavioral profiles per client device, detects compromised devices
- **ReportGenerator** — scheduled daily/weekly network health reports
- **ParentalControlAgent** — category-based filtering with natural language rules ("block social media after 9pm")
- **DNSTunnelDetector** — specialized detection of DNS tunneling and data exfiltration
- **AdlistCurator** — analyzes adlist effectiveness, recommends additions/removals

---

## 11. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Agent blocks critical infrastructure | Protected domain list (default + user-configurable); confirmation by default; rate limiting |
| API key exposure | Config file with `0600` permissions; env var alternative; key never logged |
| Database locking conflicts with FTL | Read-only SQLite connections (`?mode=ro`); WAL mode already in use |
| Runaway API costs from monitoring | Configurable poll interval; batch analysis; token budget cap |
| LLM hallucinating domain names | All blocking goes through safety guard; protected domains can't be blocked; rollback available |
| Python not available on platform | Agent is entirely optional; bash shim exits cleanly with install instructions |
| Network outage during blocking | All blocking via local FTL API (loopback); LLM unavailability = graceful degradation to cached rules |
| MCP server exposed to internet | Bind to localhost by default; require HTTPS reverse proxy for remote access; token-based auth; rate limiting |
| Unauthorized MCP access | Auth token required for HTTP transport; token stored with 0600 permissions; rotate via `--generate-token` |

---

## 12. Dependencies

**Python packages** (in `requirements-agent.txt`):
```
anthropic>=0.40.0     # Anthropic Claude SDK
openai>=1.0.0         # OpenAI-compatible SDK (also covers Ollama, etc.)
mcp[cli]>=1.0.0       # MCP Python SDK (FastMCP server framework)
requests>=2.28.0      # HTTP client for FTL API
tomli>=2.0.0          # TOML parser (Python < 3.11 backport)
```

**System requirements:**
- Python 3.9+
- Pi-hole v6+ with FTL REST API
- Network access to chosen LLM provider (or local model server)

---

## 13. Critical Reference Files

| File | Relevance |
|------|-----------|
| `pihole` (lines 548-581, 487-539) | CLI dispatch — add `agent` subcommand |
| `advanced/Scripts/api.sh` | Reference for FTL API auth/request pattern to port |
| `advanced/Scripts/list.sh` | Reference for domain add/remove API contract |
| `advanced/Scripts/query.sh` | Reference for search/query API pattern |
| `advanced/Templates/gravity.db.sql` | Database schema for gravity.db |
| `advanced/bash-completion/pihole.bash` | Must add `agent` completions |
| MCP Python SDK docs | https://modelcontextprotocol.io/docs/develop/build-server |
| Claude Desktop MCP config | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) |
