"""Read-only SQLite access to pihole-FTL.db and gravity.db.

All connections use ?mode=ro to guarantee no writes. FTL uses WAL mode,
so concurrent reads are safe and non-blocking.
"""

import sqlite3
import subprocess
import time
from typing import Any


def _get_db_path(config_key: str, default: str) -> str:
    """Resolve database path via pihole-FTL config."""
    try:
        result = subprocess.run(
            ["pihole-FTL", "--config", "-q", config_key],
            capture_output=True, text=True, timeout=5,
        )
        path = result.stdout.strip()
        return path if path else default
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return default


class PiholeDBReader:
    """Read-only access to Pi-hole's SQLite databases."""

    def __init__(self) -> None:
        self._ftl_db_path = _get_db_path("files.database", "/etc/pihole/pihole-FTL.db")
        self._gravity_db_path = _get_db_path("files.gravity", "/etc/pihole/gravity.db")

    def _connect_ro(self, db_path: str) -> sqlite3.Connection:
        """Open a read-only SQLite connection."""
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        return conn

    # ── Query Log (pihole-FTL.db) ──

    def get_recent_queries(self, hours: int = 24, limit: int = 10000) -> list[dict]:
        """Get recent DNS queries from the query_storage table."""
        cutoff = int(time.time()) - (hours * 3600)
        conn = self._connect_ro(self._ftl_db_path)
        try:
            cursor = conn.execute(
                "SELECT * FROM query_storage WHERE timestamp >= ? ORDER BY timestamp DESC LIMIT ?",
                (cutoff, limit),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_query_counts_by_domain(self, hours: int = 24) -> list[dict]:
        """Aggregate query counts by domain, sorted descending."""
        cutoff = int(time.time()) - (hours * 3600)
        conn = self._connect_ro(self._ftl_db_path)
        try:
            cursor = conn.execute(
                """SELECT domain, COUNT(*) as count
                   FROM query_storage
                   WHERE timestamp >= ?
                   GROUP BY domain
                   ORDER BY count DESC""",
                (cutoff,),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_query_counts_by_client(self, hours: int = 24) -> list[dict]:
        """Aggregate query counts by client, sorted descending."""
        cutoff = int(time.time()) - (hours * 3600)
        conn = self._connect_ro(self._ftl_db_path)
        try:
            cursor = conn.execute(
                """SELECT client, COUNT(*) as count
                   FROM query_storage
                   WHERE timestamp >= ?
                   GROUP BY client
                   ORDER BY count DESC""",
                (cutoff,),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_query_trend(self, hours: int = 24, bucket_minutes: int = 60) -> list[dict]:
        """Get query volume trend bucketed by time interval."""
        cutoff = int(time.time()) - (hours * 3600)
        bucket_seconds = bucket_minutes * 60
        conn = self._connect_ro(self._ftl_db_path)
        try:
            cursor = conn.execute(
                """SELECT (timestamp / ?) * ? as bucket, COUNT(*) as count
                   FROM query_storage
                   WHERE timestamp >= ?
                   GROUP BY bucket
                   ORDER BY bucket ASC""",
                (bucket_seconds, bucket_seconds, cutoff),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_queries_since_id(self, last_id: int, limit: int = 50000) -> list[dict]:
        """Get queries with ID greater than last_id (for polling)."""
        conn = self._connect_ro(self._ftl_db_path)
        try:
            cursor = conn.execute(
                "SELECT * FROM query_storage WHERE id > ? ORDER BY id ASC LIMIT ?",
                (last_id, limit),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    # ── Gravity DB ──

    def get_blocked_domains(self, limit: int = 1000) -> list[str]:
        """Get domains from the gravity table (blocked domains)."""
        conn = self._connect_ro(self._gravity_db_path)
        try:
            cursor = conn.execute(
                "SELECT DISTINCT domain FROM gravity LIMIT ?", (limit,)
            )
            return [row["domain"] for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_domainlist(self, type_id: int) -> list[dict]:
        """Get entries from domainlist by type.

        Types: 0=allow/exact, 1=deny/exact, 2=allow/regex, 3=deny/regex
        """
        conn = self._connect_ro(self._gravity_db_path)
        try:
            cursor = conn.execute(
                "SELECT * FROM domainlist WHERE type = ? ORDER BY id",
                (type_id,),
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()

    def get_adlist_info(self) -> list[dict]:
        """Get information about configured adlists."""
        conn = self._connect_ro(self._gravity_db_path)
        try:
            cursor = conn.execute(
                "SELECT id, address, enabled, comment, number FROM adlist ORDER BY id"
            )
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            return []
        finally:
            conn.close()
