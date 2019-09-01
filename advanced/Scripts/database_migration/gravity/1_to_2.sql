.timeout 30000

BEGIN TRANSACTION;

CREATE TABLE domain_audit
(
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	domain TEXT UNIQUE NOT NULL,
	date_added INTEGER NOT NULL DEFAULT (cast(strftime('%s', 'now') as int))
);

UPDATE info SET value = 2 WHERE property = 'version';

COMMIT;
