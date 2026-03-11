"""Pi-hole MCP Server — exposes Pi-hole agent tools to Claude Desktop and mobile.

Supports two transports:
  - stdio:  For Claude Desktop (launched as subprocess)
  - http:   For Claude mobile and remote MCP clients (Streamable HTTP)

All tools reuse the same api_client, db_reader, and safety modules as the CLI agents.
"""

import json
import math
import secrets
import sys
from collections import Counter
from typing import Optional

from mcp.server.fastmcp import FastMCP, Context

from pihole_agent.api_client import PiholeAPIClient, PiholeAPIError
from pihole_agent.config import AgentConfig
from pihole_agent.core.safety import SafetyGuard, SafetyError
from pihole_agent.db_reader import PiholeDBReader

# ── Server Instance ──────────────────────────────────────────

mcp = FastMCP(
    "Pi-hole Agent",
    instructions=(
        "Pi-hole network management server. You can query DNS traffic, "
        "analyze patterns, detect anomalies, and manage blocking rules. "
        "All mutating operations go through safety guardrails."
    ),
)


def _get_safety() -> SafetyGuard:
    return SafetyGuard.from_config()


def _get_reader() -> PiholeDBReader:
    return PiholeDBReader()


# ── MCP Tools: Statistics & Queries (read-only) ─────────────


@mcp.tool()
def get_stats_summary() -> str:
    """Get Pi-hole statistics: total queries, queries blocked, percentage blocked, and status."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("stats/summary")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_recent_queries(hours: int = 24, limit: int = 100) -> str:
    """Get recent DNS queries from the Pi-hole query log.

    Args:
        hours: How many hours back to look (default: 24)
        limit: Maximum number of queries to return (default: 100, max: 10000)
    """
    limit = min(limit, 10000)
    reader = _get_reader()
    queries = reader.get_recent_queries(hours=hours, limit=limit)
    return json.dumps(queries, indent=2, default=str)


@mcp.tool()
def get_top_domains(count: int = 10, hours: int = 24) -> str:
    """Get the most frequently queried domains over a time period.

    Args:
        count: Number of top domains to return (default: 10)
        hours: Time window in hours (default: 24)
    """
    reader = _get_reader()
    domains = reader.get_query_counts_by_domain(hours=hours)[:count]
    return json.dumps(domains, indent=2, default=str)


@mcp.tool()
def get_top_clients(count: int = 10, hours: int = 24) -> str:
    """Get the most active DNS clients (devices) over a time period.

    Args:
        count: Number of top clients to return (default: 10)
        hours: Time window in hours (default: 24)
    """
    reader = _get_reader()
    clients = reader.get_query_counts_by_client(hours=hours)[:count]
    return json.dumps(clients, indent=2, default=str)


@mcp.tool()
def search_adlists(domain: str, partial: bool = True) -> str:
    """Search Pi-hole's adlists (blocklists) for a specific domain.

    Args:
        domain: The domain to search for
        partial: Whether to allow partial matches (default: True)
    """
    try:
        with PiholeAPIClient() as client:
            data = client.get(f"search/{domain}?N=20&partial={'true' if partial else 'false'}")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_denied_domains() -> str:
    """List all domains currently on the Pi-hole deny (block) list."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("domains/deny/exact")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_allowed_domains() -> str:
    """List all domains currently on the Pi-hole allow list."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("domains/allow/exact")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_adlist_info() -> str:
    """Get information about all configured adlists (blocklist sources)."""
    reader = _get_reader()
    adlists = reader.get_adlist_info()
    return json.dumps(adlists, indent=2, default=str)


# ── MCP Tools: Analysis (read-only, computed) ───────────────


@mcp.tool()
def analyze_query_trend(hours: int = 24, bucket_minutes: int = 60) -> str:
    """Get query volume trend over time, bucketed by interval.

    Args:
        hours: Time window in hours (default: 24)
        bucket_minutes: Size of each time bucket in minutes (default: 60)
    """
    reader = _get_reader()
    trend = reader.get_query_trend(hours=hours, bucket_minutes=bucket_minutes)
    return json.dumps(trend, indent=2, default=str)


@mcp.tool()
def detect_anomalous_domains(hours: int = 24, min_queries: int = 10) -> str:
    """Detect domains with anomalous query patterns that may indicate
    DGA (Domain Generation Algorithm), DNS tunneling, or other suspicious activity.

    Uses entropy analysis and statistical outlier detection on query patterns.

    Args:
        hours: Time window in hours to analyze (default: 24)
        min_queries: Minimum query count to consider a domain (default: 10)
    """
    reader = _get_reader()
    domains = reader.get_query_counts_by_domain(hours=hours)
    if not domains:
        return json.dumps({"anomalies": [], "message": "No query data available"})

    anomalies = []
    for entry in domains:
        domain = entry.get("domain", "")
        count = entry.get("count", 0)
        if count < min_queries or not domain:
            continue

        # Shannon entropy calculation for domain labels
        labels = domain.split(".")
        main_label = labels[0] if labels else domain
        entropy = _shannon_entropy(main_label)

        # Flag high-entropy domains (potential DGA)
        is_suspicious = False
        reasons = []

        if entropy > 3.5 and len(main_label) > 10:
            is_suspicious = True
            reasons.append(f"High entropy ({entropy:.2f}) with long label — potential DGA")

        # Unusual number of subdomains (potential tunneling)
        if len(labels) > 5:
            is_suspicious = True
            reasons.append(f"Excessive subdomain depth ({len(labels)} levels) — potential DNS tunneling")

        # High consonant ratio (random-looking)
        vowels = set("aeiou")
        consonant_ratio = sum(1 for c in main_label.lower() if c.isalpha() and c not in vowels) / max(len(main_label), 1)
        if consonant_ratio > 0.75 and len(main_label) > 8:
            is_suspicious = True
            reasons.append(f"High consonant ratio ({consonant_ratio:.2f}) — random-looking domain")

        if is_suspicious:
            anomalies.append({
                "domain": domain,
                "query_count": count,
                "entropy": round(entropy, 2),
                "reasons": reasons,
            })

    # Sort by entropy descending
    anomalies.sort(key=lambda x: x["entropy"], reverse=True)

    return json.dumps({
        "anomalies": anomalies[:50],
        "total_domains_analyzed": len(domains),
        "hours_analyzed": hours,
    }, indent=2)


def _shannon_entropy(text: str) -> float:
    """Calculate Shannon entropy of a string."""
    if not text:
        return 0.0
    freq = Counter(text.lower())
    length = len(text)
    return -sum(
        (count / length) * math.log2(count / length)
        for count in freq.values()
    )


# ── MCP Tools: Blocking (mutating, safety-guarded) ──────────


@mcp.tool()
def block_domain(domain: str, comment: str = "") -> str:
    """Add a domain to Pi-hole's deny list to block DNS resolution for it.

    This is a mutating operation subject to safety guardrails:
    - Protected domains (DNS resolvers, OS updates, etc.) cannot be blocked
    - Rate limiting applies
    - Action is audit-logged

    Args:
        domain: The domain to block (e.g., "ads.example.com")
        comment: Optional comment explaining why the domain is blocked
    """
    safety = _get_safety()

    try:
        safety.check_domain_protection(domain)
        safety.check_rate_limit("block")

        policy = safety.check_blocking_policy("block_domain")
        if policy == "deny":
            safety.log_action("mcp", "system", "block_domain", domain, comment, "DENIED_BY_POLICY")
            return json.dumps({
                "status": "denied",
                "reason": f"Current blocking policy ({safety._config.blocking_mode}) does not allow this action. "
                          f"Change via: pihole agent config safety.blocking_mode confirm"
            })
    except SafetyError as e:
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        with PiholeAPIClient() as client:
            result = client.post("domains/deny/exact", {"domain": domain, "comment": comment})
        safety.log_action("mcp", "system", "block_domain", domain, comment, "OK")
        return json.dumps({"status": "blocked", "domain": domain, "result": result}, default=str)
    except PiholeAPIError as e:
        safety.log_action("mcp", "system", "block_domain", domain, comment, f"ERROR: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def unblock_domain(domain: str) -> str:
    """Remove a domain from Pi-hole's deny list to allow DNS resolution again.

    This is a mutating operation subject to safety guardrails.

    Args:
        domain: The domain to unblock
    """
    safety = _get_safety()

    try:
        safety.check_rate_limit("unblock")
        policy = safety.check_blocking_policy("unblock_domain")
        if policy == "deny":
            safety.log_action("mcp", "system", "unblock_domain", domain, "", "DENIED_BY_POLICY")
            return json.dumps({
                "status": "denied",
                "reason": f"Current blocking policy ({safety._config.blocking_mode}) does not allow this action."
            })
    except SafetyError as e:
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        with PiholeAPIClient() as client:
            result = client.post("domains:batchDelete", {"domains": [{"domain": domain, "type": "deny", "kind": "exact"}]})
        safety.log_action("mcp", "system", "unblock_domain", domain, "", "OK")
        return json.dumps({"status": "unblocked", "domain": domain, "result": result}, default=str)
    except PiholeAPIError as e:
        safety.log_action("mcp", "system", "unblock_domain", domain, "", f"ERROR: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def enable_blocking() -> str:
    """Enable Pi-hole DNS blocking (resume blocking ads/trackers)."""
    safety = _get_safety()
    try:
        with PiholeAPIClient() as client:
            result = client.post("dns/blocking", {"blocking": True})
        safety.log_action("mcp", "system", "enable_blocking", "global", "", "OK")
        return json.dumps({"status": "blocking_enabled", "result": result}, default=str)
    except PiholeAPIError as e:
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def disable_blocking(seconds: int = 0) -> str:
    """Temporarily disable Pi-hole DNS blocking.

    Args:
        seconds: Duration in seconds to disable blocking. 0 means disable indefinitely.
    """
    safety = _get_safety()

    try:
        safety.check_rate_limit("disable_blocking")
        policy = safety.check_blocking_policy("disable_blocking")
        if policy == "deny":
            safety.log_action("mcp", "system", "disable_blocking", "global", f"{seconds}s", "DENIED_BY_POLICY")
            return json.dumps({
                "status": "denied",
                "reason": f"Current blocking policy ({safety._config.blocking_mode}) does not allow this action."
            })
    except SafetyError as e:
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        data = {"blocking": False}
        if seconds > 0:
            data["timer"] = seconds
        with PiholeAPIClient() as client:
            result = client.post("dns/blocking", data)
        safety.log_action("mcp", "system", "disable_blocking", "global", f"{seconds}s", "OK")
        return json.dumps({"status": "blocking_disabled", "seconds": seconds, "result": result}, default=str)
    except PiholeAPIError as e:
        return json.dumps({"status": "error", "reason": str(e)})


# ── MCP Tools: Audit & Status ───────────────────────────────


@mcp.tool()
def get_agent_audit_log(last_n: int = 20) -> str:
    """Get the last N entries from the agent audit log showing recent agent actions.

    Args:
        last_n: Number of recent entries to retrieve (default: 20)
    """
    config = AgentConfig.load()
    from pathlib import Path
    log_path = Path(config.logging.audit_log)

    if not log_path.exists():
        return json.dumps({"entries": [], "message": "No audit log found"})

    lines = log_path.read_text().strip().splitlines()
    recent = lines[-last_n:] if len(lines) > last_n else lines

    entries = []
    for line in recent:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            entries.append({"raw": line})

    return json.dumps({"entries": entries, "total_entries": len(lines)}, indent=2)


@mcp.tool()
def get_blocking_status() -> str:
    """Get the current Pi-hole DNS blocking status (enabled or disabled)."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("dns/blocking")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_safety_config() -> str:
    """Get the current agent safety configuration including blocking policy,
    rate limits, and protected domains."""
    config = AgentConfig.load()
    safety_info = config.safety_dict()

    # Add protected domains count
    safety = SafetyGuard.from_config(config)
    safety_info["protected_domains_count"] = len(safety._protected_domains)

    return json.dumps(safety_info, indent=2)


# ── MCP Resources (live data endpoints) ─────────────────────


@mcp.resource("pihole://stats/summary")
def resource_stats_summary() -> str:
    """Current Pi-hole statistics summary — total queries, blocked, percentage."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("stats/summary"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://blocking/status")
def resource_blocking_status() -> str:
    """Current DNS blocking status (enabled/disabled)."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("dns/blocking"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://config/safety")
def resource_safety_config() -> str:
    """Current agent safety configuration."""
    config = AgentConfig.load()
    return json.dumps(config.safety_dict(), indent=2)


# ── Server Startup ──────────────────────────────────────────


def generate_auth_token() -> str:
    """Generate a secure auth token for HTTP transport."""
    return f"mcp_ph_{secrets.token_hex(32)}"


def run_server(transport: str = "stdio", host: str = "127.0.0.1", port: int = 8741) -> None:
    """Start the MCP server with the specified transport."""
    if transport == "stdio":
        mcp.run(transport="stdio")
    elif transport == "http":
        mcp.run(transport="streamable-http", host=host, port=port)
    else:
        print(f"Unknown transport: {transport}. Use 'stdio' or 'http'.", file=sys.stderr)
        sys.exit(1)
