import os
import threading

import flask
from qpython_compat import qconnection

import config


API_SCRIPT = os.path.join(os.path.dirname(__file__), "q", "web_api.q")


class QClient:

    def __init__(self):

        self.conn = qconnection.QConnection(
            host=config.Q_HOST,
            port=config.Q_PORT
        )

        self._api_loaded = False

        self._lock = threading.Lock()

    def connect(self):

        if not self.conn.is_connected():

            self.conn.open()

            self._api_loaded = False

        if not self._api_loaded:

            self.conn(f'system "l {API_SCRIPT}"')

            self._api_loaded = True

    def _force_reconnect(self):

        # is_connected() only reflects local socket state, not whether the
        # remote end is actually still there - if q crashed and a process
        # supervisor already restarted it, the old connection looks open
        # right up until a write fails with a reset/broken-pipe error.
        # Only reached from execute()'s except clause below.
        try:
            self.conn.close()
        except Exception:
            pass

        self.conn.open()

        self._api_loaded = False

        self.connect()

    def close(self):

        if self.conn.is_connected():

            self.conn.close()

    def _sync_current_user(self):

        # .web.currentUser (read by every .quiz.history insert across the
        # app, see eg .web.judge/.web.submitAnswer) tracks whoever's
        # signed in on the Flask session making this call. Synced on
        # every request rather than only at login/logout, since the q
        # process can restart independently of Flask and would otherwise
        # keep believing whoever last called .web.setCurrentUser is still
        # signed in.
        if not flask.has_request_context():

            return

        handle = flask.session.get("user_handle") or ""

        self.conn(".web.setCurrentUser", handle)

    def execute(self, expression, *parameters):

        # The underlying QConnection is a single TCP socket to q. If two
        # Flask request threads call into it at the same time, their reads
        # and writes interleave on the wire and corrupt the IPC framing -
        # the client then decodes garbage (eg a bogus "type" error) instead
        # of a real response. Serialize access per-connection to prevent it.
        with self._lock:

            self.connect()

            try:

                self._sync_current_user()

                return self.conn(expression, *parameters)

            except OSError:

                # The socket was stale (q restarted underneath us) rather
                # than this being a real q-side error - QException (a q
                # application error, eg "Unknown problem") is a separate
                # type and isn't caught here, so those still propagate
                # normally on the first try.
                self._force_reconnect()

                self._sync_current_user()

                return self.conn(expression, *parameters)