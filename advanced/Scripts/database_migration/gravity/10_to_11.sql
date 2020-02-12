.timeout 30000

BEGIN TRANSACTION;

ALTER TABLE client ADD COLUMN date_added INTEGER;
ALTER TABLE client ADD COLUMN date_modified INTEGER;
ALTER TABLE client ADD COLUMN comment TEXT;

CREATE TRIGGER tr_client_update AFTER UPDATE ON client
    BEGIN
      UPDATE client SET date_modified = (cast(strftime('%s', 'now') as int)) WHERE id = NEW.id;
    END;

UPDATE info SET value = 11 WHERE property = 'version';

COMMIT;
