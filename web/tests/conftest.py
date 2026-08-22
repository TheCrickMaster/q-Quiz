import os
import subprocess
import sys
import time

import pytest

# A dedicated port, distinct from the port the app normally runs on
# (config.Q_PORT / 5000) - tests boot their own isolated q process so they
# never touch whatever real dev/prod q server (and its live .quiz.history)
# might already be running.
TEST_Q_PORT = int(os.environ.get("TEST_Q_PORT", 5099))

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEB_DIR = os.path.join(REPO_ROOT, "web")
DEFAULT_Q_EXECUTABLE = "q" if os.name != "nt" else r"C:\q\w64\q.exe"
Q_EXECUTABLE = os.environ.get("Q_EXECUTABLE", DEFAULT_Q_EXECUTABLE)
Q_LOG_PATH = os.path.join(REPO_ROOT, "web", "tests", ".q_test_server.log")


def _q_is_ready(port, timeout_each=2):
    # A bare TCP connect can succeed while q is still mid-script (the
    # listener opens before .quiz.init[] finishes loading everything), so
    # readiness is only trusted once an actual query round-trips - probing
    # for a symbol that's only defined at the very end of the boot chain.
    sys.path.insert(0, WEB_DIR)
    from qpython_compat import qconnection

    conn = qconnection.QConnection(host="localhost", port=port, timeout=timeout_each)
    try:
        conn.open()
        # .web.currentUser is a nested-namespace global (key `. only lists
        # top-level names, so it can't be checked that way) - querying it
        # directly is enough: it only exists once scripts/init.q's boot
        # sequence has actually reached that assignment, and a q error
        # (undefined variable) during earlier boot is caught below.
        conn(".web.currentUser")
        return True
    except Exception:
        return False
    finally:
        if conn.is_connected():
            conn.close()


@pytest.fixture(scope="session")
def q_process():

    if os.path.exists(Q_LOG_PATH):
        os.remove(Q_LOG_PATH)

    log_file = open(Q_LOG_PATH, "w")

    proc = subprocess.Popen(
        [Q_EXECUTABLE, "scripts/init.q", "-p", str(TEST_Q_PORT)],
        cwd=REPO_ROOT,
        stdout=log_file,
        stderr=subprocess.STDOUT
    )

    deadline = time.time() + 60

    ready = False

    while time.time() < deadline:

        if proc.poll() is not None:
            log_file.close()
            with open(Q_LOG_PATH) as f:
                raise RuntimeError("q test server exited early:\n" + f.read())

        if _q_is_ready(TEST_Q_PORT):
            ready = True
            break

        time.sleep(0.5)

    if not ready:
        proc.terminate()
        log_file.close()
        raise RuntimeError("q test server did not become ready within 60s - see " + Q_LOG_PATH)

    yield proc

    proc.terminate()

    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()

    log_file.close()


@pytest.fixture(scope="session")
def client(q_process):

    os.environ["Q_PORT"] = str(TEST_Q_PORT)

    sys.path.insert(0, WEB_DIR)

    import app as flask_app

    flask_app.app.config["TESTING"] = True

    with flask_app.app.test_client() as test_client:
        yield test_client
