.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

ALTER TABLE regex RENAME TO regex_denylist;

CREATE TABLE regex_denylist_by_group
(
	regex_denylist_id INTEGER NOT NULL REFERENCES regex_denylist (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (regex_denylist_id, group_id)
);

INSERT INTO regex_denylist_by_group SELECT * FROM regex_by_group;
DROP TABLE regex_by_group;
DROP VIEW vw_regex;
DROP TRIGGER tr_regex_update;

CREATE VIEW vw_regex_denylist AS SELECT DISTINCT domain
    FROM regex_denylist
    LEFT JOIN regex_denylist_by_group ON regex_denylist_by_group.regex_denylist_id = regex_denylist.id
    LEFT JOIN "group" ON "group".id = regex_denylist_by_group.group_id
    WHERE regex_denylist.enabled = 1 AND (regex_denylist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_denylist.id;

CREATE TRIGGER tr_regex_denylist_update AFTER UPDATE ON regex_denylist
    BEGIN
      UPDATE regex_denylist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE TABLE regex_allowlist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT
);

CREATE TABLE regex_allowlist_by_group
(
	regex_allowlist_id INTEGER NOT NULL REFERENCES regex_allowlist (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (regex_allowlist_id, group_id)
);

CREATE VIEW vw_regex_allowlist AS SELECT DISTINCT domain
    FROM regex_allowlist
    LEFT JOIN regex_allowlist_by_group ON regex_allowlist_by_group.regex_allowlist_id = regex_allowlist.id
    LEFT JOIN "group" ON "group".id = regex_allowlist_by_group.group_id
    WHERE regex_allowlist.enabled = 1 AND (regex_allowlist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_allowlist.id;

CREATE TRIGGER tr_regex_allowlist_update AFTER UPDATE ON regex_allowlist
    BEGIN
      UPDATE regex_allowlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;


UPDATE info SET value = 3 WHERE property = 'version';

COMMIT;
