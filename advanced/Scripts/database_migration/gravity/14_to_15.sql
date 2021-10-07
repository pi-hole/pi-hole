.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP VIEW vw_adlist;

UPDATE info SET value = 15 WHERE property = 'version';

COMMIT;
