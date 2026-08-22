"""
Process supervisor for q-Quiz.

Starts the q server and the Flask/waitress web server as child processes
and restarts whichever one exits unexpectedly - the reliability gap this
closes is that q crashed and needed manual restarts repeatedly during
development, with no automatic recovery. Pure Python: no new q/kdb code,
no third-party service manager (NSSM etc.) required - if you'd rather run
this as a real Windows service, wrap it with NSSM or a Task Scheduler
"at startup" trigger; this script is what either of those would launch.

Usage (from the repo root):
    python scripts/supervisor.py

Config via env vars (all optional):
    Q_EXECUTABLE            default C:\\q\\w64\\q.exe
    Q_PORT                  default 5000
    PORT                    web port, default 8000 (passed through to wsgi.py)
    POLL_INTERVAL_SECONDS   how often to check child processes, default 5
    RESTART_BACKOFF_SECONDS pause before restarting a crashed child, default 3
"""

import os
import signal
import subprocess
import sys
import time


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WEB_DIR = os.path.join(REPO_ROOT, "web")
LOG_DIR = os.path.join(REPO_ROOT, "logs")

DEFAULT_Q_EXECUTABLE = "q" if os.name != "nt" else r"C:\q\w64\q.exe"
Q_EXECUTABLE = os.environ.get("Q_EXECUTABLE", DEFAULT_Q_EXECUTABLE)
Q_PORT = os.environ.get("Q_PORT", "5000")
PYTHON_EXECUTABLE = sys.executable
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", 5))
RESTART_BACKOFF_SECONDS = int(os.environ.get("RESTART_BACKOFF_SECONDS", 3))


def _timestamp():

    return time.strftime("%Y-%m-%d %H:%M:%S")


def _open_log(name):

    return open(os.path.join(LOG_DIR, name), "a")


def start_q():

    log = _open_log("q-server.log")

    log.write("\n=== " + _timestamp() + " starting q on port " + Q_PORT + " ===\n")

    log.flush()

    proc = subprocess.Popen(
        [Q_EXECUTABLE, "scripts/init.q", "-p", Q_PORT],
        cwd=REPO_ROOT,
        stdout=log,
        stderr=subprocess.STDOUT
    )

    return proc, log


def start_web():

    log = _open_log("web-server.log")

    log.write("\n=== " + _timestamp() + " starting web ===\n")

    log.flush()

    env = os.environ.copy()

    env["Q_PORT"] = Q_PORT

    # Otherwise print() output (including autosave.py's) sits in Python's
    # stdout buffer indefinitely once it's redirected to a file instead of
    # a terminal, making the log file look empty until the process exits.
    env["PYTHONUNBUFFERED"] = "1"

    proc = subprocess.Popen(
        [PYTHON_EXECUTABLE, "wsgi.py"],
        cwd=WEB_DIR,
        stdout=log,
        stderr=subprocess.STDOUT,
        env=env
    )

    return proc, log


def main():

    os.makedirs(LOG_DIR, exist_ok=True)

    print("Starting q-Quiz supervisor...", flush=True)

    q_proc, q_log = start_q()

    time.sleep(3)

    web_proc, web_log = start_web()

    children = {"q": (q_proc, q_log), "web": (web_proc, web_log)}

    print("q pid=" + str(q_proc.pid) + " web pid=" + str(web_proc.pid) + " - logs in " + LOG_DIR, flush=True)

    stopping = {"flag": False}

    def shutdown(signum=None, frame=None):

        if stopping["flag"]:
            return

        stopping["flag"] = True

        print("\nSupervisor stopping, terminating children...", flush=True)

        for name, (proc, log) in children.items():
            if proc.poll() is None:
                proc.terminate()

        for name, (proc, log) in children.items():
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
            log.close()

        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)

    starters = {"q": start_q, "web": start_web}

    while not stopping["flag"]:

        time.sleep(POLL_INTERVAL_SECONDS)

        for name in list(children.keys()):

            proc, log = children[name]

            if proc.poll() is not None:

                print(_timestamp() + " " + name + " exited (code " + str(proc.returncode) + "), restarting", flush=True)

                log.close()

                time.sleep(RESTART_BACKOFF_SECONDS)

                children[name] = starters[name]()


if __name__ == "__main__":
    main()
