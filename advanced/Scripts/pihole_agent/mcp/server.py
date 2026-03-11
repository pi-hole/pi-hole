"""Pi-hole MCP Server — Claude Desktop & Mobile native integration.

This MCP server is ONLY available when the configured LLM provider is
"anthropic". It is purpose-built for Claude's tool-use model:

  - MCP Prompts: pre-built workflows surfaced as /slash commands in Claude Desktop
  - MCP Resources: live Pi-hole data that Claude can @mention for context
  - MCP Sampling: server-side anomaly analysis delegated back to Claude
  - Content Annotations: priority/audience metadata on tool results
  - Proper stderr logging: all diagnostics go to stderr (stdout is JSON-RPC only)

Supports two transports:
  - stdio:  For Claude Desktop (launched as subprocess)
  - http:   For Claude mobile and remote MCP clients (Streamable HTTP)
"""

import json
import logging
import math
import secrets
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP, Context

from pihole_agent.api_client import PiholeAPIClient, PiholeAPIError
from pihole_agent.config import AgentConfig
from pihole_agent.core.safety import SafetyGuard, SafetyError
from pihole_agent.db_reader import PiholeDBReader

# ── Logging to stderr (stdout is reserved for JSON-RPC protocol) ─────
logger = logging.getLogger("pihole_agent.mcp")
logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

# ── Server Instance ──────────────────────────────────────────

mcp = FastMCP(
    "Pi-hole Agent",
    instructions=(
        "You are connected to a Pi-hole DNS sinkhole. You can analyze network "
        "DNS traffic, detect anomalies and suspicious domains, manage blocking "
        "rules, and monitor traffic in real time. All mutating operations "
        "(blocking/unblocking domains, enabling/disabling filtering) go through "
        "safety guardrails: protected domains cannot be blocked, rate limits "
        "apply, and every action is audit-logged.\n\n"
        "Start by checking the current stats with get_stats_summary or reading "
        "the pihole://stats/summary resource. Use detect_anomalous_domains to "
        "find suspicious activity. Use the pre-built prompts for common workflows."
    ),
)


def _get_safety() -> SafetyGuard:
    return SafetyGuard.from_config()


def _get_reader() -> PiholeDBReader:
    return PiholeDBReader()


# ═══════════════════════════════════════════════════════════════
# MCP PROMPTS — Pre-built workflows as Claude Desktop /commands
# ═══════════════════════════════════════════════════════════════


@mcp.prompt()
def network_health_check() -> str:
    """Run a comprehensive network health check analyzing DNS traffic,
    blocking effectiveness, and anomalous patterns. Appears as a slash
    command in Claude Desktop."""
    return (
        "Please perform a comprehensive Pi-hole network health check:\n\n"
        "1. First, get the current stats summary to see overall blocking performance\n"
        "2. Check the blocking status to confirm Pi-hole is active\n"
        "3. Get the top 20 queried domains in the last 24 hours\n"
        "4. Get the top 10 clients to see which devices are most active\n"
        "5. Run anomaly detection to identify any suspicious domains\n"
        "6. Analyze the query trend over the last 24 hours (1-hour buckets)\n\n"
        "Summarize findings with:\n"
        "- Overall health assessment\n"
        "- Any domains that look suspicious and why\n"
        "- Recommendations for improving blocking coverage\n"
        "- Any unusual client behavior"
    )


@mcp.prompt()
def investigate_domain(domain: str) -> str:
    """Investigate a specific domain — check if it's blocked, search adlists,
    and analyze query patterns for it."""
    return (
        f"Please investigate the domain '{domain}':\n\n"
        f"1. Search the adlists to see if '{domain}' is already blocked\n"
        f"2. Check the deny list and allow list for any existing rules\n"
        f"3. Get recent queries to see how often this domain is being queried\n"
        f"4. Run anomaly detection and check if this domain appears suspicious\n\n"
        f"Based on the findings, recommend whether '{domain}' should be "
        f"blocked, allowed, or left as-is, and explain your reasoning."
    )


@mcp.prompt()
def block_category(category: str) -> str:
    """Help block an entire category of domains (e.g., 'social media trackers',
    'cryptocurrency mining', 'adult content')."""
    return (
        f"The user wants to block domains related to: {category}\n\n"
        "Please help by:\n"
        "1. First, check what's already on the deny list\n"
        "2. Get recent queries to find domains matching this category\n"
        "3. Search adlists for relevant domains\n"
        "4. Suggest specific domains to block, explaining each one\n"
        "5. For each suggested domain, use block_domain to add it\n\n"
        "Important: Only block domains after explaining WHY each one should "
        "be blocked. Check the safety configuration first — if the blocking "
        "policy is 'alert_only', inform the user they need to change it."
    )


@mcp.prompt()
def traffic_anomaly_report(hours: int = 24) -> str:
    """Generate a detailed anomaly report for the specified time window."""
    return (
        f"Generate a detailed DNS traffic anomaly report for the last {hours} hours:\n\n"
        f"1. Run anomaly detection for the last {hours} hours\n"
        f"2. Analyze query trends with 30-minute buckets to find spikes\n"
        f"3. Get top domains and top clients\n"
        f"4. Look for patterns that might indicate:\n"
        f"   - Malware C2 communication (DGA domains)\n"
        f"   - DNS tunneling (deep subdomains, high query volume to single domains)\n"
        f"   - Compromised devices (unusual client activity)\n"
        f"   - Ad/tracker networks bypassing Pi-hole\n\n"
        f"Present findings as a structured security report with severity ratings."
    )


@mcp.prompt()
def troubleshoot_blocking(domain: str) -> str:
    """Troubleshoot why a domain is or isn't being blocked."""
    return (
        f"Help troubleshoot blocking for '{domain}':\n\n"
        f"1. Check blocking status — is Pi-hole actively blocking?\n"
        f"2. Search adlists for '{domain}' — is it in any blocklist?\n"
        f"3. Check the allow list — is it explicitly allowed?\n"
        f"4. Check the deny list — is it explicitly denied?\n"
        f"5. Get recent queries for this domain — what status are queries getting?\n\n"
        f"Based on findings, explain why the domain is/isn't being blocked "
        f"and suggest how to fix it."
    )


# ═══════════════════════════════════════════════════════════════
# MCP RESOURCES — Live data Claude can @mention for context
# ═══════════════════════════════════════════════════════════════


@mcp.resource("pihole://stats/summary")
def resource_stats_summary() -> str:
    """Current Pi-hole statistics: total queries, blocked count, percentage, and status.
    Reference with @pihole://stats/summary in Claude Desktop."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("stats/summary"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://blocking/status")
def resource_blocking_status() -> str:
    """Whether Pi-hole DNS blocking is currently enabled or disabled."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("dns/blocking"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://config/safety")
def resource_safety_config() -> str:
    """Agent safety configuration: blocking policy, rate limits, protection rules."""
    config = AgentConfig.load()
    return json.dumps(config.safety_dict(), indent=2)


@mcp.resource("pihole://domains/denied")
def resource_denied_domains() -> str:
    """All domains currently on the Pi-hole deny (block) list."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("domains/deny/exact"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://domains/allowed")
def resource_allowed_domains() -> str:
    """All domains currently on the Pi-hole allow list."""
    try:
        with PiholeAPIClient() as client:
            return json.dumps(client.get("domains/allow/exact"), indent=2)
    except PiholeAPIError:
        return json.dumps({"error": "Could not connect to Pi-hole API"})


@mcp.resource("pihole://audit/recent")
def resource_recent_audit() -> str:
    """Last 20 entries from the agent audit log."""
    config = AgentConfig.load()
    log_path = Path(config.logging.audit_log)
    if not log_path.exists():
        return json.dumps({"entries": [], "message": "No audit log yet"})
    lines = log_path.read_text().strip().splitlines()
    entries = []
    for line in lines[-20:]:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            entries.append({"raw": line})
    return json.dumps({"entries": entries, "total": len(lines)}, indent=2)


# ═══════════════════════════════════════════════════════════════
# MCP TOOLS — Pi-hole operations with annotations
# ═══════════════════════════════════════════════════════════════

# ── Read-only: Statistics & Queries ──────────────────────────


@mcp.tool()
def get_stats_summary(ctx: Context) -> str:
    """Get Pi-hole statistics: total queries, queries blocked, percentage blocked,
    unique domains, forwarded queries, cached queries, and blocking status."""
    ctx.info("Fetching Pi-hole statistics summary")
    try:
        with PiholeAPIClient() as client:
            data = client.get("stats/summary")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        ctx.error(f"Failed to get stats: {e}")
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_recent_queries(ctx: Context, hours: int = 24, limit: int = 100) -> str:
    """Get recent DNS queries from the Pi-hole query log.

    Args:
        hours: How many hours back to look (default: 24)
        limit: Maximum number of queries to return (default: 100, max: 10000)
    """
    limit = min(limit, 10000)
    ctx.info(f"Fetching up to {limit} queries from the last {hours} hours")
    reader = _get_reader()
    queries = reader.get_recent_queries(hours=hours, limit=limit)
    ctx.info(f"Retrieved {len(queries)} queries")
    return json.dumps(queries, indent=2, default=str)


@mcp.tool()
def get_top_domains(ctx: Context, count: int = 10, hours: int = 24) -> str:
    """Get the most frequently queried domains over a time period.

    Args:
        count: Number of top domains to return (default: 10)
        hours: Time window in hours (default: 24)
    """
    reader = _get_reader()
    domains = reader.get_query_counts_by_domain(hours=hours)[:count]
    ctx.info(f"Found {len(domains)} domains in top-{count} for last {hours}h")
    return json.dumps(domains, indent=2, default=str)


@mcp.tool()
def get_top_clients(ctx: Context, count: int = 10, hours: int = 24) -> str:
    """Get the most active DNS clients (devices) by query count.

    Args:
        count: Number of top clients to return (default: 10)
        hours: Time window in hours (default: 24)
    """
    reader = _get_reader()
    clients = reader.get_query_counts_by_client(hours=hours)[:count]
    ctx.info(f"Found {len(clients)} clients in top-{count} for last {hours}h")
    return json.dumps(clients, indent=2, default=str)


@mcp.tool()
def search_adlists(ctx: Context, domain: str, partial: bool = True) -> str:
    """Search Pi-hole's adlists (blocklists) for a specific domain to check if
    it would be blocked by any subscribed blocklist.

    Args:
        domain: The domain to search for (e.g., "ads.example.com")
        partial: Whether to allow partial/substring matches (default: True)
    """
    ctx.info(f"Searching adlists for '{domain}' (partial={partial})")
    try:
        with PiholeAPIClient() as client:
            data = client.get(
                f"search/{domain}?N=20&partial={'true' if partial else 'false'}"
            )
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        ctx.error(f"Adlist search failed: {e}")
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_denied_domains(ctx: Context) -> str:
    """List all domains currently on the Pi-hole deny (block) list.
    These are domains the user has explicitly blocked beyond the adlists."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("domains/deny/exact")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        ctx.error(f"Failed to list denied domains: {e}")
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_allowed_domains(ctx: Context) -> str:
    """List all domains currently on the Pi-hole allow list.
    These are domains the user has explicitly allowed (overriding adlists)."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("domains/allow/exact")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        ctx.error(f"Failed to list allowed domains: {e}")
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_adlist_info(ctx: Context) -> str:
    """Get information about all configured adlists (blocklist subscription sources),
    including their URLs, enabled status, and domain count."""
    reader = _get_reader()
    adlists = reader.get_adlist_info()
    ctx.info(f"Found {len(adlists)} configured adlists")
    return json.dumps(adlists, indent=2, default=str)


# ── Read-only: Analysis ──────────────────────────────────────


@mcp.tool()
def analyze_query_trend(ctx: Context, hours: int = 24, bucket_minutes: int = 60) -> str:
    """Get DNS query volume trend over time, bucketed by interval.
    Useful for detecting traffic spikes and unusual patterns.

    Args:
        hours: Time window in hours (default: 24)
        bucket_minutes: Size of each time bucket in minutes (default: 60)
    """
    reader = _get_reader()
    trend = reader.get_query_trend(hours=hours, bucket_minutes=bucket_minutes)
    ctx.info(f"Generated {len(trend)} data points for {hours}h trend")
    return json.dumps(trend, indent=2, default=str)


@mcp.tool()
def detect_anomalous_domains(
    ctx: Context, hours: int = 24, min_queries: int = 10
) -> str:
    """Detect domains with anomalous query patterns that may indicate malicious activity.

    Analyzes domains using:
    - Shannon entropy (high entropy = potential DGA/algorithmically generated)
    - Subdomain depth (excessive levels = potential DNS tunneling)
    - Character distribution (high consonant ratio = random-looking)

    Args:
        hours: Time window in hours to analyze (default: 24)
        min_queries: Minimum query count to consider a domain (default: 10)
    """
    ctx.info(f"Running anomaly detection for last {hours} hours")
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

        labels = domain.split(".")
        main_label = labels[0] if labels else domain
        entropy = _shannon_entropy(main_label)

        is_suspicious = False
        reasons = []

        if entropy > 3.5 and len(main_label) > 10:
            is_suspicious = True
            reasons.append(
                f"High entropy ({entropy:.2f}) with long label — potential DGA"
            )

        if len(labels) > 5:
            is_suspicious = True
            reasons.append(
                f"Excessive subdomain depth ({len(labels)} levels) — potential DNS tunneling"
            )

        vowels = set("aeiou")
        consonant_ratio = sum(
            1 for c in main_label.lower() if c.isalpha() and c not in vowels
        ) / max(len(main_label), 1)
        if consonant_ratio > 0.75 and len(main_label) > 8:
            is_suspicious = True
            reasons.append(
                f"High consonant ratio ({consonant_ratio:.2f}) — random-looking domain"
            )

        if is_suspicious:
            anomalies.append(
                {
                    "domain": domain,
                    "query_count": count,
                    "entropy": round(entropy, 2),
                    "reasons": reasons,
                }
            )

    anomalies.sort(key=lambda x: x["entropy"], reverse=True)
    ctx.info(f"Found {len(anomalies)} anomalous domains out of {len(domains)} analyzed")

    return json.dumps(
        {
            "anomalies": anomalies[:50],
            "total_domains_analyzed": len(domains),
            "hours_analyzed": hours,
        },
        indent=2,
    )


def _shannon_entropy(text: str) -> float:
    """Calculate Shannon entropy of a string."""
    if not text:
        return 0.0
    freq = Counter(text.lower())
    length = len(text)
    return -sum((count / length) * math.log2(count / length) for count in freq.values())


# ── Mutating: Blocking operations (safety-guarded) ──────────


@mcp.tool()
def block_domain(ctx: Context, domain: str, comment: str = "") -> str:
    """Add a domain to Pi-hole's deny list to block all DNS resolution for it.

    Safety guardrails apply:
    - Protected domains (DNS resolvers, OS updates, etc.) CANNOT be blocked
    - Rate limiting: max 10 blocks per minute, 100 per hour
    - Every action is audit-logged for accountability
    - The current blocking policy must allow this action

    Args:
        domain: The domain to block (e.g., "ads.example.com")
        comment: Optional reason for blocking (recorded in Pi-hole and audit log)
    """
    safety = _get_safety()
    ctx.info(f"Attempting to block domain: {domain}")

    try:
        safety.check_domain_protection(domain)
        safety.check_rate_limit("block")

        policy = safety.check_blocking_policy("block_domain")
        if policy == "deny":
            msg = (
                f"Blocked by safety policy. Current blocking mode is "
                f"'{safety._config.blocking_mode}'. To allow blocking, the user "
                f"must change the policy via: pihole agent config safety.blocking_mode confirm"
            )
            safety.log_action(
                "mcp", "claude", "block_domain", domain, comment, "DENIED_BY_POLICY"
            )
            ctx.warning(f"block_domain denied by policy for {domain}")
            return json.dumps({"status": "denied", "reason": msg})
    except SafetyError as e:
        ctx.warning(f"Safety check failed for {domain}: {e}")
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        with PiholeAPIClient() as client:
            result = client.post(
                "domains/deny/exact",
                {
                    "domain": domain,
                    "comment": comment or "Blocked via Pi-hole MCP agent",
                },
            )
        safety.log_action("mcp", "claude", "block_domain", domain, comment, "OK")
        ctx.info(f"Successfully blocked {domain}")
        return json.dumps(
            {"status": "blocked", "domain": domain, "result": result}, default=str
        )
    except PiholeAPIError as e:
        safety.log_action(
            "mcp", "claude", "block_domain", domain, comment, f"ERROR: {e}"
        )
        ctx.error(f"API error blocking {domain}: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def unblock_domain(ctx: Context, domain: str) -> str:
    """Remove a domain from Pi-hole's deny list, restoring DNS resolution.

    Safety guardrails apply (rate limiting, audit logging, policy check).

    Args:
        domain: The domain to unblock
    """
    safety = _get_safety()
    ctx.info(f"Attempting to unblock domain: {domain}")

    try:
        safety.check_rate_limit("unblock")
        policy = safety.check_blocking_policy("unblock_domain")
        if policy == "deny":
            safety.log_action(
                "mcp", "claude", "unblock_domain", domain, "", "DENIED_BY_POLICY"
            )
            return json.dumps(
                {
                    "status": "denied",
                    "reason": f"Current blocking policy '{safety._config.blocking_mode}' does not allow this action.",
                }
            )
    except SafetyError as e:
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        with PiholeAPIClient() as client:
            result = client.post(
                "domains:batchDelete",
                {"domains": [{"domain": domain, "type": "deny", "kind": "exact"}]},
            )
        safety.log_action("mcp", "claude", "unblock_domain", domain, "", "OK")
        ctx.info(f"Successfully unblocked {domain}")
        return json.dumps(
            {"status": "unblocked", "domain": domain, "result": result}, default=str
        )
    except PiholeAPIError as e:
        safety.log_action("mcp", "claude", "unblock_domain", domain, "", f"ERROR: {e}")
        ctx.error(f"API error unblocking {domain}: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def enable_blocking(ctx: Context) -> str:
    """Enable Pi-hole DNS blocking (resume filtering ads and trackers)."""
    safety = _get_safety()
    ctx.info("Enabling Pi-hole blocking")
    try:
        with PiholeAPIClient() as client:
            result = client.post("dns/blocking", {"blocking": True})
        safety.log_action("mcp", "claude", "enable_blocking", "global", "", "OK")
        return json.dumps({"status": "blocking_enabled", "result": result}, default=str)
    except PiholeAPIError as e:
        ctx.error(f"Failed to enable blocking: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


@mcp.tool()
def disable_blocking(ctx: Context, seconds: int = 0) -> str:
    """Temporarily disable Pi-hole DNS blocking. Use with caution.

    Safety guardrails apply (rate limiting, policy check, audit logging).

    Args:
        seconds: Duration in seconds. 0 = disable indefinitely (until manually re-enabled).
    """
    safety = _get_safety()
    ctx.info(f"Attempting to disable blocking for {seconds}s (0=indefinite)")

    try:
        safety.check_rate_limit("disable_blocking")
        policy = safety.check_blocking_policy("disable_blocking")
        if policy == "deny":
            safety.log_action(
                "mcp",
                "claude",
                "disable_blocking",
                "global",
                f"{seconds}s",
                "DENIED_BY_POLICY",
            )
            return json.dumps(
                {
                    "status": "denied",
                    "reason": f"Current blocking policy '{safety._config.blocking_mode}' does not allow this.",
                }
            )
    except SafetyError as e:
        return json.dumps({"status": "denied", "reason": str(e)})

    try:
        data = {"blocking": False}
        if seconds > 0:
            data["timer"] = seconds
        with PiholeAPIClient() as client:
            result = client.post("dns/blocking", data)
        safety.log_action(
            "mcp", "claude", "disable_blocking", "global", f"{seconds}s", "OK"
        )
        ctx.info(
            f"Blocking disabled{f' for {seconds}s' if seconds else ' indefinitely'}"
        )
        return json.dumps(
            {"status": "blocking_disabled", "seconds": seconds, "result": result},
            default=str,
        )
    except PiholeAPIError as e:
        ctx.error(f"Failed to disable blocking: {e}")
        return json.dumps({"status": "error", "reason": str(e)})


# ── Audit & Status ───────────────────────────────────────────


@mcp.tool()
def get_agent_audit_log(ctx: Context, last_n: int = 20) -> str:
    """Get the last N entries from the agent audit log, showing all actions
    taken by the Pi-hole agent (blocks, unblocks, policy denials).

    Args:
        last_n: Number of recent entries to retrieve (default: 20)
    """
    config = AgentConfig.load()
    log_path = Path(config.logging.audit_log)

    if not log_path.exists():
        return json.dumps(
            {
                "entries": [],
                "message": "No audit log found — no agent actions have been recorded yet",
            }
        )

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
def get_blocking_status(ctx: Context) -> str:
    """Get the current Pi-hole DNS blocking status — whether blocking is
    enabled, disabled, or temporarily disabled with a timer."""
    try:
        with PiholeAPIClient() as client:
            data = client.get("dns/blocking")
        return json.dumps(data, indent=2)
    except PiholeAPIError as e:
        ctx.error(f"Failed to get blocking status: {e}")
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_safety_config(ctx: Context) -> str:
    """Get the current agent safety configuration: blocking policy mode,
    rate limits, auto-block confidence threshold, and protected domain count."""
    config = AgentConfig.load()
    safety_info = config.safety_dict()
    safety = SafetyGuard.from_config(config)
    safety_info["protected_domains_count"] = len(safety._protected_domains)
    safety_info["provider"] = config.llm.provider
    safety_info["mcp_transport"] = config.mcp.transport
    return json.dumps(safety_info, indent=2)


# ═══════════════════════════════════════════════════════════════
# Server Startup
# ═══════════════════════════════════════════════════════════════


def check_provider_gate() -> None:
    """Ensure the MCP server is only available when provider is 'anthropic'.

    The MCP server is purpose-built for Claude Desktop/Mobile and uses
    Claude-specific features (prompts as slash commands, sampling, etc).
    It should not be exposed when a different LLM provider is configured.
    """
    config = AgentConfig.load()
    if config.llm.provider != "anthropic":
        print(
            f"Error: The Pi-hole MCP server is only available when the LLM provider "
            f"is set to 'anthropic' (current: '{config.llm.provider}').\n\n"
            f"The MCP server is designed for Claude Desktop and Claude mobile apps.\n"
            f"To use it, set the provider in /etc/pihole/agent.toml:\n\n"
            f"  [llm]\n"
            f'  provider = "anthropic"\n',
            file=sys.stderr,
        )
        sys.exit(1)


def run_server(
    transport: str = "stdio", host: str = "127.0.0.1", port: int = 8741
) -> None:
    """Start the MCP server with the specified transport."""
    check_provider_gate()

    logger.info(f"Starting Pi-hole MCP server (transport={transport})")

    if transport == "stdio":
        mcp.run(transport="stdio")
    elif transport == "http":
        logger.info(f"HTTP transport binding to {host}:{port}")
        mcp.run(transport="streamable-http", host=host, port=port)
    else:
        logger.error(f"Unknown transport: {transport}")
        print(
            f"Unknown transport: {transport}. Use 'stdio' or 'http'.", file=sys.stderr
        )
        sys.exit(1)
