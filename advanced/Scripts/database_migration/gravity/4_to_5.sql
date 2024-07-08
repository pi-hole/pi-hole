.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP TABLE gravity;
CREATE TABLE gravity
(
    domain TEXT NOT NULL,
    adlist_id INTEGER NOT NULL REFERENCES adlist (id),
    PRIMARY KEY(domain, adlist_id)
);

DROP VIEW vw_gravity;
CREATE VIEW vw_gravity AS SELECT domain, adlist_by_group.group_id AS group_id
    FROM gravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = gravity.adlist_id
    LEFT JOIN adlist ON adlist.id = gravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1);

CREATE TABLE client
(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT NOL NULL UNIQUE
);

CREATE TABLE client_by_group
(
    client_id INTEGER NOT NULL REFERENCES client (id),
    group_id INTEGER NOT NULL REFERENCES "group" (id),
    PRIMARY KEY (client_id, group_id)
);

UPDATE info SET value = 5 WHERE property = 'version';

COMMIT;
