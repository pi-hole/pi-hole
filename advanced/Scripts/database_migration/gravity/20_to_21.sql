.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

/* These tables are keyed by their entire content, so the implicit rowid only
   adds a second lookup. The rows go through a temporary table because an
   ALTER TABLE ... RENAME reparses the schema while the views still point at
   the table being replaced */
CREATE TEMP TABLE domainlist_by_group_copy AS SELECT * FROM domainlist_by_group;
DROP TABLE domainlist_by_group;
CREATE TABLE domainlist_by_group
(
    domainlist_id INTEGER NOT NULL REFERENCES domainlist (id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
    PRIMARY KEY (domainlist_id, group_id)
) WITHOUT ROWID;
INSERT INTO domainlist_by_group SELECT * FROM domainlist_by_group_copy;
DROP TABLE domainlist_by_group_copy;
CREATE INDEX idx_domainlist_by_group_gid ON domainlist_by_group (group_id, domainlist_id);

CREATE TEMP TABLE adlist_by_group_copy AS SELECT * FROM adlist_by_group;
DROP TABLE adlist_by_group;
CREATE TABLE adlist_by_group
(
    adlist_id INTEGER NOT NULL REFERENCES adlist (id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
    PRIMARY KEY (adlist_id, group_id)
) WITHOUT ROWID;
INSERT INTO adlist_by_group SELECT * FROM adlist_by_group_copy;
DROP TABLE adlist_by_group_copy;
CREATE INDEX idx_adlist_by_group_gid ON adlist_by_group (group_id, adlist_id);

CREATE TEMP TABLE client_by_group_copy AS SELECT * FROM client_by_group;
DROP TABLE client_by_group;
CREATE TABLE client_by_group
(
    client_id INTEGER NOT NULL REFERENCES client (id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES "group" (id) ON DELETE CASCADE,
    PRIMARY KEY (client_id, group_id)
) WITHOUT ROWID;
INSERT INTO client_by_group SELECT * FROM client_by_group_copy;
DROP TABLE client_by_group_copy;

CREATE TEMP TABLE info_copy AS SELECT * FROM info;
DROP TABLE info;
CREATE TABLE info
(
    property TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
INSERT INTO info SELECT * FROM info_copy;
DROP TABLE info_copy;

/* Match the row by id: matching by content refreshed date_modified of every
   entry carrying the same name */
DROP TRIGGER tr_client_update;
CREATE TRIGGER tr_client_update AFTER UPDATE ON client
    BEGIN
      UPDATE client SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

DROP TRIGGER tr_domainlist_update;
CREATE TRIGGER tr_domainlist_update AFTER UPDATE ON domainlist
    BEGIN
      UPDATE domainlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

/* Nothing depends on the order of these views, and sorting them costs a
   temporary B-tree on every lookup */
DROP VIEW vw_allowlist;
CREATE VIEW vw_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 0;

DROP VIEW vw_denylist;
CREATE VIEW vw_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 1;

DROP VIEW vw_regex_allowlist;
CREATE VIEW vw_regex_allowlist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 2;

DROP VIEW vw_regex_denylist;
CREATE VIEW vw_regex_denylist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 3;

UPDATE info SET value = 21 WHERE property = 'version';

COMMIT;
