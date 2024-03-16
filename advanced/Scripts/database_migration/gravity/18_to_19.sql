.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP TRIGGER tr_domainlist_delete;
CREATE TRIGGER tr_domainlist_delete BEFORE DELETE ON domainlist
    BEGIN
      DELETE FROM domainlist_by_group WHERE domainlist_id = OLD.id;
    END;

DROP TRIGGER tr_adlist_delete;
CREATE TRIGGER tr_adlist_delete BEFORE DELETE ON adlist
    BEGIN
      DELETE FROM adlist_by_group WHERE adlist_id = OLD.id;
    END;

DROP TRIGGER tr_client_delete;
CREATE TRIGGER tr_client_delete BEFORE DELETE ON client
    BEGIN
      DELETE FROM client_by_group WHERE client_id = OLD.id;
    END;

UPDATE info SET value = 19 WHERE property = 'version';

COMMIT;
