.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

ALTER TABLE adlist ADD COLUMN date_updated INTEGER;

DROP TRIGGER tr_adlist_update;

CREATE TRIGGER tr_adlist_update AFTER UPDATE OF address,enabled,comment ON adlist
    BEGIN
      UPDATE adlist SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

UPDATE info SET value = 13 WHERE property = 'version';

COMMIT;
