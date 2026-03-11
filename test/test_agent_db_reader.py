"""Tests for the Pi-hole agent database reader.

Uses in-memory SQLite databases to test query logic without requiring
a running Pi-hole instance.
"""

import os
import sqlite3
import sys
import time

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "advanced", "Scripts"))

from pihole_agent.db_reader import PiholeDBReader


@pytest.fixture
def ftl_db(tmp_path):
    """Create a temporary pihole-FTL.db with query_storage table."""
    db_path = tmp_path / "pihole-FTL.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("""CREATE TABLE query_storage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            domain TEXT,
            client TEXT,
            type INTEGER DEFAULT 1,
            status INTEGER DEFAULT 2
        )""")
    now = int(time.time())
    rows = [
        (now - 100, "google.com", "192.168.1.10", 1, 2),
        (now - 200, "google.com", "192.168.1.10", 1, 2),
        (now - 300, "facebook.com", "192.168.1.20", 1, 2),
        (now - 400, "ads.example.com", "192.168.1.10", 1, 5),
        (now - 500, "tracker.evil.com", "192.168.1.30", 1, 5),
        (now - 86000, "old-query.com", "192.168.1.10", 1, 2),  # ~24h ago
        (now - 172800, "ancient.com", "192.168.1.10", 1, 2),  # 48h ago
    ]
    conn.executemany(
        "INSERT INTO query_storage (timestamp, domain, client, type, status) VALUES (?,?,?,?,?)",
        rows,
    )
    conn.commit()
    conn.close()
    return str(db_path)


@pytest.fixture
def gravity_db(tmp_path):
    """Create a temporary gravity.db with domainlist and gravity tables."""
    db_path = tmp_path / "gravity.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("""CREATE TABLE domainlist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type INTEGER,
            domain TEXT,
            enabled INTEGER DEFAULT 1,
            comment TEXT DEFAULT ''
        )""")
    conn.execute("""CREATE TABLE gravity (
            domain TEXT
        )""")
    conn.execute("""CREATE TABLE adlist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            address TEXT,
            enabled INTEGER DEFAULT 1,
            comment TEXT DEFAULT '',
            number INTEGER DEFAULT 0
        )""")
    # domainlist: type 0=allow/exact, 1=deny/exact, 2=allow/regex, 3=deny/regex
    conn.executemany(
        "INSERT INTO domainlist (type, domain, comment) VALUES (?,?,?)",
        [
            (1, "blocked.example.com", "test block"),
            (1, "another-blocked.com", "another block"),
            (0, "allowed.example.com", "test allow"),
            (3, r".*\.tracking\.com$", "regex deny"),
        ],
    )
    conn.executemany(
        "INSERT INTO gravity (domain) VALUES (?)",
        [("gravity-blocked.com",), ("ads.trackernetwork.com",)],
    )
    conn.executemany(
        "INSERT INTO adlist (address, enabled, comment, number) VALUES (?,?,?,?)",
        [
            ("https://example.com/hosts.txt", 1, "Test list", 1000),
            ("https://ads.example.com/list.txt", 0, "Disabled list", 500),
        ],
    )
    conn.commit()
    conn.close()
    return str(db_path)


@pytest.fixture
def reader(ftl_db, gravity_db, monkeypatch):
    """Create a PiholeDBReader with test databases."""
    reader = PiholeDBReader.__new__(PiholeDBReader)
    reader._ftl_db_path = ftl_db
    reader._gravity_db_path = gravity_db
    return reader


# ── Query Log Tests ───────────────────────────────────────────


class TestRecentQueries:
    def test_returns_recent_queries(self, reader):
        """get_recent_queries returns queries within the time window."""
        queries = reader.get_recent_queries(hours=1)
        assert len(queries) == 5  # excludes 24h+ old queries

    def test_respects_hours_parameter(self, reader):
        """Queries older than the specified hours are excluded."""
        queries = reader.get_recent_queries(hours=48)
        assert len(queries) == 7  # includes all queries

    def test_respects_limit(self, reader):
        """Limit parameter caps the number of results."""
        queries = reader.get_recent_queries(hours=48, limit=3)
        assert len(queries) == 3

    def test_returns_dicts(self, reader):
        """Results are dictionaries with expected keys."""
        queries = reader.get_recent_queries(hours=1, limit=1)
        assert len(queries) == 1
        q = queries[0]
        assert "domain" in q
        assert "client" in q
        assert "timestamp" in q


class TestQueryCountsByDomain:
    def test_aggregates_by_domain(self, reader):
        """Domains are aggregated with correct counts."""
        counts = reader.get_query_counts_by_domain(hours=1)
        domains = {c["domain"]: c["count"] for c in counts}
        assert domains["google.com"] == 2
        assert domains["facebook.com"] == 1

    def test_sorted_descending(self, reader):
        """Results are sorted by count descending."""
        counts = reader.get_query_counts_by_domain(hours=1)
        for i in range(len(counts) - 1):
            assert counts[i]["count"] >= counts[i + 1]["count"]


class TestQueryCountsByClient:
    def test_aggregates_by_client(self, reader):
        """Clients are aggregated with correct counts."""
        counts = reader.get_query_counts_by_client(hours=1)
        clients = {c["client"]: c["count"] for c in counts}
        # 192.168.1.10 has 3 queries within 1h (google x2, ads.example x1)
        assert clients["192.168.1.10"] == 3
        assert clients["192.168.1.20"] == 1
        assert clients["192.168.1.30"] == 1


class TestQueryTrend:
    def test_returns_bucketed_data(self, reader):
        """Query trend returns time-bucketed counts."""
        trend = reader.get_query_trend(hours=1, bucket_minutes=60)
        assert len(trend) >= 1
        for entry in trend:
            assert "bucket" in entry
            assert "count" in entry


class TestQueriesSinceId:
    def test_returns_queries_after_id(self, reader):
        """get_queries_since_id returns only queries with id > last_id."""
        all_queries = reader.get_recent_queries(hours=48, limit=10000)
        if all_queries:
            mid_id = all_queries[len(all_queries) // 2]["id"]
            newer = reader.get_queries_since_id(mid_id)
            for q in newer:
                assert q["id"] > mid_id


# ── Gravity DB Tests ──────────────────────────────────────────


class TestBlockedDomains:
    def test_returns_gravity_domains(self, reader):
        """get_blocked_domains returns domains from the gravity table."""
        domains = reader.get_blocked_domains()
        assert "gravity-blocked.com" in domains
        assert "ads.trackernetwork.com" in domains

    def test_respects_limit(self, reader):
        domains = reader.get_blocked_domains(limit=1)
        assert len(domains) == 1


class TestDomainlist:
    def test_returns_deny_exact(self, reader):
        """type_id=1 returns exact deny entries."""
        entries = reader.get_domainlist(type_id=1)
        assert len(entries) == 2
        domains = [e["domain"] for e in entries]
        assert "blocked.example.com" in domains

    def test_returns_allow_exact(self, reader):
        """type_id=0 returns exact allow entries."""
        entries = reader.get_domainlist(type_id=0)
        assert len(entries) == 1
        assert entries[0]["domain"] == "allowed.example.com"

    def test_returns_regex_deny(self, reader):
        """type_id=3 returns regex deny entries."""
        entries = reader.get_domainlist(type_id=3)
        assert len(entries) == 1


class TestAdlistInfo:
    def test_returns_adlists(self, reader):
        """get_adlist_info returns all configured adlists."""
        adlists = reader.get_adlist_info()
        assert len(adlists) == 2
        assert adlists[0]["address"] == "https://example.com/hosts.txt"
        assert adlists[0]["enabled"] == 1
        assert adlists[1]["enabled"] == 0


# ── Error Handling ────────────────────────────────────────────


class TestErrorHandling:
    def test_missing_database_returns_empty(self, tmp_path):
        """Missing database files return empty results, not exceptions."""
        reader = PiholeDBReader.__new__(PiholeDBReader)
        reader._ftl_db_path = str(tmp_path / "nonexistent.db")
        reader._gravity_db_path = str(tmp_path / "nonexistent.db")
        assert reader.get_recent_queries() == []
        assert reader.get_query_counts_by_domain() == []
        assert reader.get_blocked_domains() == []
