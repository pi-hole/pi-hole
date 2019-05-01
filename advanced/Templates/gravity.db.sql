CREATE TABLE whitelist (domain TEXT UNIQUE NOT NULL,  enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE blacklist (domain TEXT UNIQUE NOT NULL,  enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE regex     (domain TEXT UNIQUE NOT NULL,  enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE adlists   (address TEXT UNIQUE NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), date_modified INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE gravity   (domain TEXT UNIQUE NOT NULL);
CREATE TABLE info      (property TEXT NOT NULL, value TEXT NOT NULL);

INSERT INTO info VALUES("version","1");

CREATE VIEW vw_gravity AS SELECT a.domain
    FROM gravity a
    WHERE a.domain NOT IN (SELECT domain from whitelist WHERE enabled == 1);

CREATE VIEW vw_whitelist AS SELECT a.domain
    FROM whitelist a
    WHERE a.enabled == 1;
CREATE TRIGGER tr_whitelist_update AFTER UPDATE ON whitelist
    BEGIN
      UPDATE whitelist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_blacklist AS SELECT a.domain
    FROM blacklist a
    WHERE a.enabled == 1 AND a.domain NOT IN vw_whitelist;
CREATE TRIGGER tr_blacklist_update AFTER UPDATE ON blacklist
    BEGIN
      UPDATE blacklist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_regex AS SELECT a.domain
    FROM regex a
    WHERE a.enabled == 1;
CREATE TRIGGER tr_regex_update AFTER UPDATE ON regex
    BEGIN
      UPDATE regex SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE domain = NEW.domain;
    END;

CREATE VIEW vw_adlists AS SELECT a.address
    FROM adlists a
    WHERE a.enabled == 1;
CREATE TRIGGER tr_adlists_update AFTER UPDATE ON adlists
    BEGIN
      UPDATE adlists SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE address = NEW.address;
    END;

