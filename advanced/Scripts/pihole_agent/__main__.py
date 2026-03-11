"""Pi-hole AI Agent — CLI entry point.

Usage:
    pihole agent analyze [--hours N]
    pihole agent chat
    pihole agent monitor [--daemon] [--interval N]
    pihole agent monitor --stop
    pihole agent mcp [--transport stdio|http] [--port N] [--host ADDR]
    pihole agent mcp --generate-token
    pihole agent status
    pihole agent rollback [N]
    pihole agent config [key] [value]
    pihole agent log [--tail N]
    pihole agent --help
"""

import argparse
import sys


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="pihole agent",
        description="Pi-hole AI Agent — network analysis and management",
    )
    subparsers = parser.add_subparsers(dest="command", help="Agent commands")

    # ── pihole agent mcp ──
    mcp_parser = subparsers.add_parser(
        "mcp",
        help="Start MCP server for Claude Desktop/Mobile (requires provider=anthropic)",
    )
    mcp_parser.add_argument(
        "--transport",
        choices=["stdio", "http"],
        default="stdio",
        help="Transport mode: stdio (Claude Desktop) or http (mobile/remote)",
    )
    mcp_parser.add_argument(
        "--port", type=int, default=8741, help="Port for HTTP transport"
    )
    mcp_parser.add_argument(
        "--host", default="127.0.0.1", help="Bind address for HTTP transport"
    )
    mcp_parser.add_argument(
        "--generate-token",
        action="store_true",
        help="Generate a new auth token for HTTP transport",
    )

    # ── pihole agent analyze ──
    analyze_parser = subparsers.add_parser(
        "analyze", help="One-shot DNS traffic analysis"
    )
    analyze_parser.add_argument(
        "--hours", type=int, default=24, help="Hours of data to analyze"
    )

    # ── pihole agent chat ──
    subparsers.add_parser("chat", help="Interactive conversation with the agent")

    # ── pihole agent monitor ──
    monitor_parser = subparsers.add_parser(
        "monitor", help="Real-time traffic monitoring"
    )
    monitor_parser.add_argument(
        "--daemon", action="store_true", help="Run as background daemon"
    )
    monitor_parser.add_argument(
        "--stop", action="store_true", help="Stop monitoring daemon"
    )
    monitor_parser.add_argument(
        "--interval", type=int, default=60, help="Poll interval in seconds"
    )

    # ── pihole agent status ──
    subparsers.add_parser("status", help="Show agent configuration and status")

    # ── pihole agent rollback ──
    rollback_parser = subparsers.add_parser(
        "rollback", help="Undo recent agent blocking actions"
    )
    rollback_parser.add_argument(
        "n", nargs="?", type=int, default=1, help="Number of actions to undo"
    )

    # ── pihole agent config ──
    config_parser = subparsers.add_parser("config", help="View/set agent configuration")
    config_parser.add_argument(
        "key", nargs="?", help="Configuration key (e.g., safety.blocking_mode)"
    )
    config_parser.add_argument("value", nargs="?", help="New value to set")

    # ── pihole agent log ──
    log_parser = subparsers.add_parser("log", help="View agent audit log")
    log_parser.add_argument(
        "--tail", type=int, default=20, help="Number of recent entries"
    )

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    if args.command == "mcp":
        _handle_mcp(args)
    elif args.command == "status":
        _handle_status()
    elif args.command == "log":
        _handle_log(args)
    elif args.command == "config":
        _handle_config(args)
    else:
        # Placeholder for commands implemented in later phases
        print(
            f"The '{args.command}' command will be available after Phase {_phase_for(args.command)} implementation."
        )
        print("Currently available: mcp, status, log, config")
        sys.exit(0)


def _handle_mcp(args: argparse.Namespace) -> None:
    """Start the MCP server or generate a token."""
    if args.generate_token:
        from pihole_agent.mcp.auth import generate_token, save_token_to_config

        token = generate_token()
        save_token_to_config(token)
        return

    from pihole_agent.mcp.server import run_server

    run_server(transport=args.transport, host=args.host, port=args.port)


def _handle_status() -> None:
    """Show agent status and configuration summary."""
    from pihole_agent.config import AgentConfig

    config = AgentConfig.load()
    print("Pi-hole AI Agent Status")
    print("=" * 40)
    print(f"  LLM Provider:     {config.llm.provider}")
    print(f"  Model:            {config.llm.model}")
    print(f"  API Key:          {'configured' if config.llm.api_key else 'NOT SET'}")
    print(f"  Blocking Mode:    {config.safety.blocking_mode}")
    print(
        f"  Rate Limit:       {config.safety.rate_limit_per_minute}/min, {config.safety.rate_limit_per_hour}/hr"
    )
    print(f"  MCP Transport:    {config.mcp.transport}")
    print(f"  MCP Port:         {config.mcp.port}")
    print(f"  MCP Auth Token:   {'configured' if config.mcp.auth_token else 'NOT SET'}")
    print(f"  Audit Log:        {config.logging.audit_log}")
    print()

    # Check Pi-hole API connectivity
    from pihole_agent.api_client import PiholeAPIClient, PiholeAPIError

    try:
        with PiholeAPIClient() as client:
            stats = client.get("stats/summary")
        print("  Pi-hole API:      connected")
    except (PiholeAPIError, Exception) as e:
        print(f"  Pi-hole API:      ERROR — {e}")


def _handle_log(args: argparse.Namespace) -> None:
    """Display recent audit log entries."""
    import json
    from pathlib import Path
    from pihole_agent.config import AgentConfig

    config = AgentConfig.load()
    log_path = Path(config.logging.audit_log)

    if not log_path.exists():
        print("No audit log found.")
        return

    lines = log_path.read_text().strip().splitlines()
    recent = lines[-args.tail :] if len(lines) > args.tail else lines

    print(f"Last {len(recent)} audit log entries (of {len(lines)} total):")
    print("-" * 60)
    for line in recent:
        try:
            entry = json.loads(line)
            ts = entry.get("timestamp", "?")
            action = entry.get("action", "?")
            target = entry.get("target", "?")
            status = entry.get("status", "?")
            source = entry.get("source", "?")
            print(f"  {ts} | {source} | {action} | {target} | {status}")
        except json.JSONDecodeError:
            print(f"  {line}")


def _handle_config(args: argparse.Namespace) -> None:
    """View or set configuration values."""
    from pihole_agent.config import AgentConfig

    config = AgentConfig.load()

    if args.key is None:
        # Show all config
        import json

        print(
            json.dumps(
                {
                    "llm": {"provider": config.llm.provider, "model": config.llm.model},
                    "safety": config.safety_dict(),
                    "mcp": {
                        "transport": config.mcp.transport,
                        "port": config.mcp.port,
                        "host": config.mcp.host,
                    },
                    "monitor": {"poll_interval": config.monitor.poll_interval_seconds},
                },
                indent=2,
            )
        )
    elif args.value is None:
        # Show specific key
        parts = args.key.split(".")
        section = getattr(config, parts[0], None)
        if section and len(parts) > 1:
            val = getattr(section, parts[1], "NOT FOUND")
            print(f"{args.key} = {val}")
        else:
            print(f"Unknown config key: {args.key}")
    else:
        print(f"Setting {args.key} = {args.value}")
        print("Note: Config file editing will be implemented in a future phase.")
        print(f"For now, edit /etc/pihole/agent.toml directly.")


def _phase_for(command: str) -> int:
    phases = {"analyze": 3, "chat": 3, "monitor": 4, "rollback": 3}
    return phases.get(command, 6)


if __name__ == "__main__":
    main()
