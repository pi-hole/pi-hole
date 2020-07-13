.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

ALTER TABLE adlist ADD COLUMN date_updated INTEGER;

UPDATE info SET value = 13 WHERE property = 'version';

COMMIT;