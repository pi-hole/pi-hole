.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP TRIGGER IF EXISTS tr_group_update;
DROP TRIGGER IF EXISTS tr_group_zero;

PRAGMA legacy_alter_table=ON;
ALTER TABLE "group" RENAME TO "group__";
PRAGMA legacy_alter_table=OFF;
ALTER TABLE "group__" RENAME TO "group";

CREATE TRIGGER tr_group_update AFTER UPDATE ON "group"
    BEGIN
      UPDATE "group" SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

CREATE TRIGGER tr_group_zero AFTER DELETE ON "group"
    BEGIN
      INSERT OR IGNORE INTO "group" (id,enabled,name) VALUES (0,1,'Unassociated');
    END;

UPDATE info SET value = 9 WHERE property = 'version';

COMMIT;
