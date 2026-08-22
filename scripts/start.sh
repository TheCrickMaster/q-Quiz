#!/usr/bin/env bash
#
# Launches q-Quiz: the q server and the waitress-served web app, via
# scripts/supervisor.py (which restarts either one if it exits
# unexpectedly). This is a thin wrapper - it just resolves the repo
# root so the script works from any cwd, and offers --q-port/--port
# as a convenient way to run on alternate ports (e.g. for testing
# alongside an already-running dev instance) without having to
# remember supervisor.py's env var names.
#
# Usage:
#   scripts/start.sh                        # defaults: q=5000, web=8000
#   scripts/start.sh --q-port 5099 --port 8099
#   Q_EXECUTABLE=/path/to/q scripts/start.sh
#
# Anything supervisor.py itself reads from the environment (Q_EXECUTABLE,
# AUTOSAVE_INTERVAL_SECONDS, POLL_INTERVAL_SECONDS, GOOGLE_CLIENT_ID, ...)
# can still be set the normal way; --q-port/--port just set Q_PORT/PORT
# for you.

set -euo pipefail

usage() {
    echo "Usage: $0 [--q-port PORT] [--port PORT]"
    echo ""
    echo "  --q-port PORT   port for the q server (default 5000, or \$Q_PORT if set)"
    echo "  --port PORT     port for the web app (default 8000, or \$PORT if set)"
    echo ""
    echo "Any other supervisor.py env var (Q_EXECUTABLE, AUTOSAVE_INTERVAL_SECONDS,"
    echo "POLL_INTERVAL_SECONDS, GOOGLE_CLIENT_ID, ...) can be set as usual."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --q-port)
            Q_PORT="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export Q_PORT="${Q_PORT:-5000}"
export PORT="${PORT:-8000}"

echo "Starting q-Quiz from $REPO_ROOT (q on port $Q_PORT, web on port $PORT)..."

exec python scripts/supervisor.py
