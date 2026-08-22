#!/usr/bin/env bash
#
# Stops a running q-Quiz instance started via scripts/start.sh /
# scripts/supervisor.py. There's no pidfile anywhere, so this finds
# the supervisor process by matching its command line, tries a
# graceful stop first (supervisor.py has its own SIGINT handler that
# terminates its q/web children cleanly, which in turn lets
# web/autosave.py's on-exit hook save .quiz.history before anything
# dies), and falls back to a forceful whole-tree kill if that isn't
# possible.
#
# That fallback is the common case on Windows for a supervisor started
# via `nohup scripts/start.sh &`: it ends up with no console attached,
# so `taskkill` without /F fails outright (not a timeout) rather than
# actually delivering a graceful stop signal - confirmed empirically
# while building this, not assumed.
#
# Uses PowerShell (Get-CimInstance) rather than wmic for process
# discovery - wmic's plain-text table output has been observed to
# render with every character space-padded depending on codepage,
# which makes it too fragile to parse reliably in a script.
#
# Usage:
#   scripts/stop.sh                  # stop every running q-Quiz instance
#   scripts/stop.sh --q-port 5099    # stop only the instance whose q server is on that port
#   scripts/stop.sh --force          # skip the graceful attempt, kill immediately

set -uo pipefail

usage() {
    echo "Usage: $0 [--q-port PORT] [--force]"
    echo ""
    echo "  --q-port PORT   only stop the instance whose q server is on this port"
    echo "                  (default: stop every running q-Quiz instance)"
    echo "  --force         skip the graceful shutdown attempt, kill immediately"
}

TARGET_Q_PORT=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --q-port)
            TARGET_Q_PORT="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
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

if ! command -v powershell.exe >/dev/null 2>&1; then
    # Not Windows - fall back to a portable pgrep/pkill approach for a
    # Linux/Mac/WSL deployment (this repo's k8s/docker sketch targets
    # Linux containers, even though scripts/supervisor.py itself
    # defaults to a Windows q.exe path).
    if command -v pkill >/dev/null 2>&1; then
        echo "Stopping q-Quiz (pkill -f scripts/supervisor.py)..."
        pkill -f "scripts/supervisor.py" || echo "No running q-Quiz supervisor found."
        exit 0
    fi
    echo "Neither powershell.exe nor pkill is available - stop the supervisor process manually." >&2
    exit 1
fi

find_supervisors() {
    powershell.exe -NoProfile -Command \
        'Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "python.exe" -and $_.CommandLine -match "supervisor\.py" } | ForEach-Object { "$($_.ProcessId)|$($_.CommandLine)" }' \
        2>/dev/null | tr -d '\r'
}

q_port_of_supervisor() {
    local pid="$1"
    powershell.exe -NoProfile -Command \
        "Get-CimInstance Win32_Process | Where-Object { \$_.ParentProcessId -eq $pid -and \$_.Name -eq 'q.exe' } | ForEach-Object { \$_.CommandLine }" \
        2>/dev/null | tr -d '\r'
}

is_alive() {
    local pid="$1"
    powershell.exe -NoProfile -Command \
        "if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { 'ALIVE' }" \
        2>/dev/null | tr -d '\r'
}

stop_one() {
    local pid="$1"

    if [[ "$FORCE" -eq 0 ]]; then
        echo "Stopping supervisor (pid $pid) gracefully..."

        if taskkill //PID "$pid" >/dev/null 2>&1; then
            for _ in 1 2 3 4 5 6 7 8; do
                [[ -z "$(is_alive "$pid")" ]] && { echo "Stopped cleanly."; return 0; }
                sleep 1
            done
            echo "Still running after a graceful stop request - forcing..."
        else
            echo "Graceful stop isn't possible for this process (no console attached - typical for one started via nohup); forcing..."
        fi
    fi

    # Forceful, whole-tree kill - the supervisor's q.exe/wsgi.py
    # children are separate processes a plain taskkill //F (without
    # /T) wouldn't reach.
    taskkill //F //T //PID "$pid" >/dev/null 2>&1 || true
    echo "Stopped (forced)."
}

mapfile -t SUPERVISOR_ROWS < <(find_supervisors)

if [[ ${#SUPERVISOR_ROWS[@]} -eq 0 || -z "${SUPERVISOR_ROWS[0]}" ]]; then
    echo "No running q-Quiz supervisor found."
    exit 0
fi

STOPPED_ANY=0

for row in "${SUPERVISOR_ROWS[@]}"; do
    [[ -z "$row" ]] && continue
    pid="${row%%|*}"

    if [[ -n "$TARGET_Q_PORT" ]]; then
        q_cmdline="$(q_port_of_supervisor "$pid")"
        [[ "$q_cmdline" != *"-p $TARGET_Q_PORT"* ]] && continue
    fi

    stop_one "$pid"
    STOPPED_ANY=1
done

if [[ "$STOPPED_ANY" -eq 0 ]]; then
    echo "No matching q-Quiz instance found${TARGET_Q_PORT:+ on q port $TARGET_Q_PORT}."
fi
