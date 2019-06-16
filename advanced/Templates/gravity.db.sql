PRAGMA FOREIGN_KEYS=ON;

CREATE TABLE domain_groups
(
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"enabled" BOOLEAN NOT NULL DEFAULT 1,
	"description" TEXT
);
INSERT INTO domain_groups ("id","description") VALUES (0,'Standard group');

CREATE TABLE whitelist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	group_id INTEGER NOT NULL DEFAULT 0,
	comment TEXT,
	FOREIGN KEY (group_id) REFERENCES domain_groups(id)
);
CREATE TABLE blacklist
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	group_id INTEGER NOT NULL DEFAULT 0,
	comment TEXT,
	FOREIGN KEY (group_id) REFERENCES domain_groups(id)
);
CREATE TABLE regex
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	group_id INTEGER NOT NULL DEFAULT 0,
	comment TEXT,
	FOREIGN KEY (group_id) REFERENCES domain_groups(id)
);

CREATE TABLE adlist_groups
(
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"enabled" BOOLEAN NOT NULL DEFAULT 1,
	"description" TEXT
);
INSERT INTO adlist_groups ("id","description") VALUES (0,'Standard group');

CREATE TABLE adlists
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	address TEXT UNIQUE NOT NULL,
	enabled BOOLEAN NOT NULL DEFAULT 1,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)),
	group_id INTEGER NOT NULL DEFAULT 0,
	comment TEXT,
	FOREIGN KEY (group_id) REFERENCES adlist_groups(id)
);
CREATE TABLE gravity
(
	domain TEXT PRIMARY KEY
);
CREATE TABLE info
(
	property TEXT PRIMARY KEY,
	value TEXT NOT NULL
);

INSERT INTO info VALUES("version","1");

CREATE VIEW vw_gravity AS SELECT a.domain
    FROM gravity a
    WHERE a.domain NOT IN (SELECT domain from whitelist WHERE enabled == 1);

CREATE VIEW vw_whitelist AS SELECT a.domain
    FROM whitelist a
    INNER JOIN domain_groups b ON b.id = a.group_id
    WHERE a.enabled = 1 AND b.enabled = 1
    ORDER BY a.id;

CREATE TRIGGER tr_whitelist_update AFTER UPDATE ON whitelist
    BEGIN
      UPDATE whitelist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_blacklist AS SELECT a.domain
    FROM blacklist a
    INNER JOIN domain_groups b ON b.id = a.group_id
    WHERE a.enabled = 1 AND a.domain NOT IN vw_whitelist AND b.enabled = 1
    ORDER BY a.id;

CREATE TRIGGER tr_blacklist_update AFTER UPDATE ON blacklist
    BEGIN
      UPDATE blacklist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_regex AS SELECT a.domain
    FROM regex a
    INNER JOIN domain_groups b ON b.id = a.group_id
    WHERE a.enabled = 1 AND b.enabled = 1
    ORDER BY a.id;

CREATE TRIGGER tr_regex_update AFTER UPDATE ON regex
    BEGIN
      UPDATE regex SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_adlists AS SELECT a.address
    FROM adlists a
    INNER JOIN adlist_groups b ON b.id = a.group_id
    WHERE a.enabled = 1 AND b.enabled = 1
    ORDER BY a.id;

CREATE TRIGGER tr_adlists_update AFTER UPDATE ON adlists
    BEGIN
      UPDATE adlists SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE address = NEW.address;
    END;

