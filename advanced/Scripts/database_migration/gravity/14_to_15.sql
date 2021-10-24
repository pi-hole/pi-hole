.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;
DROP VIEW vw_adlist;

CREATE VIEW vw_adlist AS SELECT DISTINCT address, id
    FROM adlist
    WHERE enabled = 1
    ORDER BY id;

UPDATE info SET value = 15 WHERE property = 'version';

COMMIT;
