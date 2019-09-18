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

DROP VIEW vw_whitelist;
CREATE VIEW vw_whitelist AS SELECT domain, whitelist.id AS id, whitelist_by_group.group_id AS group_id
    FROM whitelist
    LEFT JOIN whitelist_by_group ON whitelist_by_group.whitelist_id = whitelist.id
    LEFT JOIN "group" ON "group".id = whitelist_by_group.group_id
    WHERE whitelist.enabled = 1 AND (whitelist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY whitelist.id;

DROP VIEW vw_blacklist;
CREATE VIEW vw_blacklist AS SELECT domain, blacklist.id AS id, blacklist_by_group.group_id AS group_id
    FROM blacklist
    LEFT JOIN blacklist_by_group ON blacklist_by_group.blacklist_id = blacklist.id
    LEFT JOIN "group" ON "group".id = blacklist_by_group.group_id
    WHERE blacklist.enabled = 1 AND (blacklist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY blacklist.id;

DROP VIEW vw_regex_whitelist;
CREATE VIEW vw_regex_whitelist AS SELECT DISTINCT domain, regex_whitelist.id AS id, regex_whitelist_by_group.group_id AS group_id
    FROM regex_whitelist
    LEFT JOIN regex_whitelist_by_group ON regex_whitelist_by_group.regex_whitelist_id = regex_whitelist.id
    LEFT JOIN "group" ON "group".id = regex_whitelist_by_group.group_id
    WHERE regex_whitelist.enabled = 1 AND (regex_whitelist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_whitelist.id;

DROP VIEW vw_regex_blacklist;
CREATE VIEW vw_regex_blacklist AS SELECT DISTINCT domain, regex_blacklist.id AS id, regex_blacklist_by_group.group_id AS group_id
    FROM regex_blacklist
    LEFT JOIN regex_blacklist_by_group ON regex_blacklist_by_group.regex_blacklist_id = regex_blacklist.id
    LEFT JOIN "group" ON "group".id = regex_blacklist_by_group.group_id
    WHERE regex_blacklist.enabled = 1 AND (regex_blacklist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY regex_blacklist.id;

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

UPDATE info SET value = 4 WHERE property = 'version';

COMMIT;
