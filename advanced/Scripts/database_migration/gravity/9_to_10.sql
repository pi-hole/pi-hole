.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

DROP TABLE IF EXISTS allowlist;
DROP TABLE IF EXISTS denylist;
DROP TABLE IF EXISTS regex_allowlist;
DROP TABLE IF EXISTS regex_denylist;

CREATE TRIGGER tr_domainlist_delete AFTER DELETE ON domainlist
    BEGIN
      DELETE FROM domainlist_by_group WHERE domainlist_id = OLD.id;
    END;

CREATE TRIGGER tr_adlist_delete AFTER DELETE ON adlist
    BEGIN
      DELETE FROM adlist_by_group WHERE adlist_id = OLD.id;
    END;

CREATE TRIGGER tr_client_delete AFTER DELETE ON client
    BEGIN
      DELETE FROM client_by_group WHERE client_id = OLD.id;
    END;

UPDATE info SET value = 10 WHERE property = 'version';

COMMIT;
