.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

CREATE TABLE domainlist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	type INTEGER NOT NULL DEFAULT 0,
	domain TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT
);

ALTER TABLE allowlist ADD COLUMN type INTEGER;
UPDATE allowlist SET type = 0;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM allowlist;

ALTER TABLE denylist ADD COLUMN type INTEGER;
UPDATE denylist SET type = 1;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM denylist;

ALTER TABLE regex_allowlist ADD COLUMN type INTEGER;
UPDATE regex_allowlist SET type = 2;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM regex_allowlist;

ALTER TABLE regex_denylist ADD COLUMN type INTEGER;
UPDATE regex_denylist SET type = 3;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM regex_denylist;

DROP TABLE allowlist_by_group;
DROP TABLE denylist_by_group;
DROP TABLE regex_allowlist_by_group;
DROP TABLE regex_denylist_by_group;
CREATE TABLE domainlist_by_group
(
	domainlist_id INTEGER NOT NULL REFERENCES domainlist (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (domainlist_id, group_id)
);

DROP TRIGGER tr_allowlist_update;
DROP TRIGGER tr_denylist_update;
DROP TRIGGER tr_regex_allowlist_update;
DROP TRIGGER tr_regex_denylist_update;
CREATE TRIGGER tr_domainlist_update AFTER UPDATE ON domainlist
    BEGIN
      UPDATE domainlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

DROP VIEW vw_allowlist;
CREATE VIEW vw_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 0
    ORDER BY domainlist.id;

DROP VIEW vw_denylist;
CREATE VIEW vw_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 1
    ORDER BY domainlist.id;

DROP VIEW vw_regex_allowlist;
CREATE VIEW vw_regex_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 2
    ORDER BY domainlist.id;

DROP VIEW vw_regex_denylist;
CREATE VIEW vw_regex_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 3
    ORDER BY domainlist.id;

UPDATE info SET value = 4 WHERE property = 'version';

COMMIT;
