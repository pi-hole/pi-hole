.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

ALTER TABLE regex RENAME TO regex_blacklist;

CREATE TABLE regex_blacklist_by_group
(
    regex_blacklist_id INTEGER NOT NULL REFERENCES regex_blacklist (id),
    group_id INTEGER NOT NULL REFERENCES "group" (id),
    PRIMARY KEY (regex_blacklist_id, group_id)
);

INSERT INTO regex_blacklist_by_group SELECT * FROM regex_by_group;
DROP TABLE regex_by_group;
DROP VIEW vw_regex;
DROP TRIGGER tr_regex_update;

CREATE VIEW vw_regex_blacklist AS SELECT DISTINCT domain
    FROM regex_blacklist
    LEFT JOIN regex_blacklist_by_group ON regex_blacklist_by_group.regex_blacklist_id = regex_blacklist.id
    LEFT JOIN "group" ON "group".id = regex_blacklist_by_group.group_id
    WHERE regex_blacklist.enabled = 1 AND (regex_blacklist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_blacklist.id;

CREATE TRIGGER tr_regex_blacklist_update AFTER UPDATE ON regex_blacklist
    BEGIN
      UPDATE regex_blacklist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE TABLE regex_whitelist
(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT UNIQUE NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT 1,
    date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
    date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
    comment TEXT
);

CREATE TABLE regex_whitelist_by_group
(
    regex_whitelist_id INTEGER NOT NULL REFERENCES regex_whitelist (id),
    group_id INTEGER NOT NULL REFERENCES "group" (id),
    PRIMARY KEY (regex_whitelist_id, group_id)
);

CREATE VIEW vw_regex_whitelist AS SELECT DISTINCT domain
    FROM regex_whitelist
    LEFT JOIN regex_whitelist_by_group ON regex_whitelist_by_group.regex_whitelist_id = regex_whitelist.id
    LEFT JOIN "group" ON "group".id = regex_whitelist_by_group.group_id
    WHERE regex_whitelist.enabled = 1 AND (regex_whitelist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_whitelist.id;

CREATE TRIGGER tr_regex_whitelist_update AFTER UPDATE ON regex_whitelist
    BEGIN
      UPDATE regex_whitelist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;


UPDATE info SET value = 3 WHERE property = 'version';

COMMIT;
