.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP VIEW vw_gravity;
CREATE VIEW vw_gravity AS SELECT domain, adlist.id AS adlist_id, adlist_by_group.group_id AS group_id
    FROM gravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = gravity.adlist_id
    LEFT JOIN adlist ON adlist.id = gravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1);

DROP VIEW vw_antigravity;
CREATE VIEW vw_antigravity AS SELECT domain, adlist.id AS adlist_id, adlist_by_group.group_id AS group_id
    FROM antigravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = antigravity.adlist_id
    LEFT JOIN adlist ON adlist.id = antigravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1) AND adlist.type = 1;

UPDATE info SET value = 18 WHERE property = 'version';

COMMIT;
