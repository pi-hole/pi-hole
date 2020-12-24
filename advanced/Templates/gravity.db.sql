PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

CREATE TABLE "group"
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	name TEXT UNIQUE NOT NULL,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	description TEXT
);
INSERT INTO "group" (id,enabled,name,description) VALUES (0,1,'Default','The default group');

CREATE TABLE domainlist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	type INTEGER NOT NULL DEFAULT 0,
	domain TEXT NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT,
	UNIQUE(domain, type)
);

CREATE TABLE adlist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	address TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT,
	date_updated INTEGER
);

CREATE TABLE adlist_by_group
(
	adlist_id INTEGER NOT NULL REFERENCES adlist (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (adlist_id, group_id)
);

CREATE TABLE gravity
(
	domain TEXT NOT NULL,
	adlist_id INTEGER NOT NULL REFERENCES adlist (id)
);

CREATE TABLE info
(
	property TEXT PRIMARY KEY,
	value TEXT NOT NULL
);

INSERT INTO "info" VALUES('version','13');

CREATE TABLE domain_audit
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int))
);

CREATE TABLE domainlist_by_group
(
	domainlist_id INTEGER NOT NULL REFERENCES domainlist (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (domainlist_id, group_id)
);

CREATE TABLE client
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	ip TEXT NOT NULL UNIQUE,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	comment TEXT
);

CREATE TABLE client_by_group
(
	client_id INTEGER NOT NULL REFERENCES client (id),
	group_id INTEGER NOT NULL REFERENCES "group" (id),
	PRIMARY KEY (client_id, group_id)
);

CREATE TRIGGER tr_adlist_update AFTER UPDATE OF address,enabled,comment ON adlist
    BEGIN
      UPDATE adlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_client_update AFTER UPDATE ON client
    BEGIN
      UPDATE client SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE ip = NEW.ip;
    END;

CREATE TRIGGER tr_domainlist_update AFTER UPDATE ON domainlist
    BEGIN
      UPDATE domainlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_whitelist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 0
    ORDER BY domainlist.id;

CREATE VIEW vw_blacklist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 1
    ORDER BY domainlist.id;

CREATE VIEW vw_regex_whitelist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 2
    ORDER BY domainlist.id;

CREATE VIEW vw_regex_blacklist AS SELECT domain, domainlist.id AS id, domainlist_by_group.group_id AS group_id
    FROM domainlist
    LEFT JOIN domainlist_by_group ON domainlist_by_group.domainlist_id = domainlist.id
    LEFT JOIN "group" ON "group".id = domainlist_by_group.group_id
    WHERE domainlist.enabled = 1 AND (domainlist_by_group.group_id IS NULL OR "group".enabled = 1)
    AND domainlist.type = 3
    ORDER BY domainlist.id;

CREATE VIEW vw_gravity AS SELECT domain, adlist_by_group.group_id AS group_id
    FROM gravity
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = gravity.adlist_id
    LEFT JOIN adlist ON adlist.id = gravity.adlist_id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1);

CREATE VIEW vw_adlist AS SELECT DISTINCT address, adlist.id AS id
    FROM adlist
    LEFT JOIN adlist_by_group ON adlist_by_group.adlist_id = adlist.id
    LEFT JOIN "group" ON "group".id = adlist_by_group.group_id
    WHERE adlist.enabled = 1 AND (adlist_by_group.group_id IS NULL OR "group".enabled = 1)
    ORDER BY adlist.id;

CREATE TRIGGER tr_domainlist_add AFTER INSERT ON domainlist
    BEGIN
      INSERT INTO domainlist_by_group (domainlist_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_client_add AFTER INSERT ON client
    BEGIN
      INSERT INTO client_by_group (client_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_adlist_add AFTER INSERT ON adlist
    BEGIN
      INSERT INTO adlist_by_group (adlist_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_group_update AFTER UPDATE ON "group"
    BEGIN
      UPDATE "group" SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_group_zero AFTER DELETE ON "group"
    BEGIN
      INSERT OR IGNORE INTO "group" (id,enabled,name) VALUES (0,1,'Default');
    END;

CREATE TRIGGER tr_domainlist_delete AFTER DELETE ON domainlist
    BEGIN
      DELETE FROM domainlist_by_group WHERE domainlist_id = OLD.id;
    END;

CREATE TRIGGER tr_adlist_delete AFTER DELETE ON adlist
    BEGIN
      DELETE FROM adlist_by_group WHERE adlist_id = OLD.id;
    END;

CREATE TRIGGER tr_client_delete AFTER DELETE ON client
    BEGIN
      DELETE FROM client_by_group WHERE client_id = OLD.id;
    END;

COMMIT;
