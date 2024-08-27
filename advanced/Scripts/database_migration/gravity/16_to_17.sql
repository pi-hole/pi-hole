.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

ALTER TABLE adlist ADD COLUMN type INTEGER NOT NULL DEFAULT 0;

UPDATE adlist SET type = 0;

CREATE TABLE IF NOT EXISTS antigravity
(
    domain TEXT NOT NULL,
    adlist_id INTEGER NOT NULL REFERENCES adlist (id)
);

CREATE VIEW vw_antigravity AS SELECT domain, adlist_by_group.group_id AS group_id
    FROM antigravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = antigravity.adlist_id
    LEFT JOIN adlist ON adlist.id = antigravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1) AND adlist.type = 1;

DROP VIEW vw_adlist;

CREATE VIEW vw_adlist AS SELECT DISTINCT address, id, type
    FROM adlist
    WHERE enabled = 1
    ORDER BY id;

UPDATE info SET value = 17 WHERE property = 'version';

COMMIT;
