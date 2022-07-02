.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

UPDATE "group" SET name = 'Default' WHERE id = 0;
UPDATE "group" SET description = 'The default group' WHERE id = 0;

DROP TRIGGER IF EXISTS tr_group_zero;

CREATE TRIGGER tr_group_zero AFTER DELETE ON "group"
    BEGIN
      INSERT OR IGNORE INTO "group" (id,enabled,name,description) VALUES (0,1,'Default','The default group');
    END;

UPDATE info SET value = 12 WHERE property = 'version';

COMMIT;
