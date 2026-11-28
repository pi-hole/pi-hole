.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

/* These tables are keyed by their entire content, so the implicit rowid and
   separate covering index duplicate every domain on disk. Copy through a
   temporary table to avoid ALTER TABLE ... RENAME reparsing views. */
CREATE TEMP TABLE gravity_copy AS SELECT domain, adlist_id FROM gravity;
DROP TABLE gravity;
CREATE TABLE gravity
(
    domain TEXT NOT NULL,
    adlist_id INTEGER NOT NULL REFERENCES adlist (id),
    PRIMARY KEY (domain, adlist_id)
) WITHOUT ROWID;
INSERT OR IGNORE INTO gravity SELECT domain, adlist_id FROM gravity_copy;
DROP TABLE gravity_copy;

CREATE TEMP TABLE antigravity_copy AS SELECT domain, adlist_id FROM antigravity;
DROP TABLE antigravity;
CREATE TABLE antigravity
(
    domain TEXT NOT NULL,
    adlist_id INTEGER NOT NULL REFERENCES adlist (id),
    PRIMARY KEY (domain, adlist_id)
) WITHOUT ROWID;
INSERT OR IGNORE INTO antigravity SELECT domain, adlist_id FROM antigravity_copy;
DROP TABLE antigravity_copy;

UPDATE info SET value = 22 WHERE property = 'version';

COMMIT;
