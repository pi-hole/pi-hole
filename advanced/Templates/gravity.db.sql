CREATE TABLE whitelist (domain TEXT UNIQUE NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE blacklist (domain TEXT UNIQUE NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE regex     (domain TEXT UNIQUE NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE adlists   (address TEXT UNIQUE NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1, date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int)), comment TEXT);
CREATE TABLE gravity   (domain TEXT UNIQUE NOT NULL);
CREATE TABLE info      (property TEXT NOT NULL, value TEXT NOT NULL);

INSERT INTO info VALUES("version","1");

CREATE VIEW vw_gravity AS SELECT DISTINCT a.domain
FROM gravity a
WHERE a.domain NOT IN (SELECT domain from whitelist WHERE enabled == 1);

CREATE VIEW vw_blacklist AS SELECT DISTINCT a.domain
FROM blacklist a
WHERE a.enabled == 1 AND
      a.domain NOT IN (SELECT domain from whitelist WHERE enabled == 1);

CREATE VIEW vw_whitelist AS SELECT DISTINCT a.domain
FROM whitelist a
WHERE a.enabled == 1;

CREATE VIEW vw_regex AS SELECT DISTINCT a.filter
FROM regex a
WHERE a.enabled == 1;
