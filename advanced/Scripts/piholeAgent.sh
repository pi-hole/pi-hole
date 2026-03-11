#!/usr/bin/env bash

# Pi-hole: A black hole for Internet advertisements
# (c) 2024 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# AI Agent CLI wrapper — validates Python environment and delegates
# to the pihole_agent Python package.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"

# Check Python 3 availability
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required for Pi-hole AI Agent functionality."
    echo "Install with: sudo apt-get install python3 python3-pip"
    exit 1
fi

# Check minimum Python version (3.9+)
if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" 2>/dev/null; then
    echo "Error: Python 3.9 or later is required for Pi-hole AI Agent."
    echo "Current version: $(python3 --version)"
    exit 1
fi

# Check for required packages (on first run)
if ! python3 -c "import mcp" 2>/dev/null; then
    echo "Required Python packages are not installed."
    echo "Install with: pip3 install -r ${PI_HOLE_SCRIPT_DIR}/pihole_agent/requirements.txt"
    echo ""
    echo "Or install individually:"
    echo "  pip3 install 'mcp[cli]>=1.0.0' 'anthropic>=0.40.0' 'openai>=1.0.0' 'requests>=2.28.0'"
    exit 1
fi

# Run the agent module
PYTHONPATH="${PI_HOLE_SCRIPT_DIR}" exec python3 -m pihole_agent "$@"
