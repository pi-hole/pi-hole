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

ALTER TABLE whitelist ADD COLUMN type INTEGER;
UPDATE whitelist SET type = 0;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM whitelist;

ALTER TABLE blacklist ADD COLUMN type INTEGER;
UPDATE blacklist SET type = 1;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM blacklist;

ALTER TABLE regex_whitelist ADD COLUMN type INTEGER;
UPDATE regex_whitelist SET type = 2;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM regex_whitelist;

ALTER TABLE regex_blacklist ADD COLUMN type INTEGER;
UPDATE regex_blacklist SET type = 3;
INSERT INTO domainlist (type,domain,enabled,date_added,date_modified,comment)
    SELECT type,domain,enabled,date_added,date_modified,comment FROM regex_blacklist;

DROP TABLE whitelist_by_group;
DROP TABLE blacklist_by_group;
DROP TABLE regex_whitelist_by_group;
DROP TABLE regex_blacklist_by_group;
CREATE TABLE domainlist_by_group
(
    domainlist_id INTEGER NOT NULL REFERENCES domainlist (id),
    group_id INTEGER NOT NULL REFERENCES "group" (id),
    PRIMARY KEY (domainlist_id, group_id)
);

DROP TRIGGER tr_whitelist_update;
DROP TRIGGER tr_blacklist_update;
DROP TRIGGER tr_regex_whitelist_update;
DROP TRIGGER tr_regex_blacklist_update;
CREATE TRIGGER tr_domainlist_update AFTER UPDATE ON domainlist
    BEGIN
      UPDATE domainlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

DROP VIEW vw_whitelist;
CREATE VIEW vw_whitelist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 0
    ORDER BY domainlist.id;

DROP VIEW vw_blacklist;
CREATE VIEW vw_blacklist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 1
    ORDER BY domainlist.id;

DROP VIEW vw_regex_whitelist;
CREATE VIEW vw_regex_whitelist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 2
    ORDER BY domainlist.id;

DROP VIEW vw_regex_blacklist;
CREATE VIEW vw_regex_blacklist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 3
    ORDER BY domainlist.id;

UPDATE info SET value = 4 WHERE property = 'version';

COMMIT;
