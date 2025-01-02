.timeout 30000

ATTACH DATABASE '/etc/pihole/gravity.db' AS OLD;

BEGIN TRANSACTION;

DROP TRIGGER tr_domainlist_add;
DROP TRIGGER tr_client_add;
DROP TRIGGER tr_adlist_add;

INSERT OR REPLACE INTO "group" SELECT * FROM OLD."group";

INSERT OR REPLACE INTO domainlist SELECT * FROM OLD.domainlist;
DELETE FROM OLD.domainlist_by_group WHERE domainlist_id NOT IN (SELECT id FROM OLD.domainlist);
INSERT OR REPLACE INTO domainlist_by_group SELECT * FROM OLD.domainlist_by_group;

INSERT OR REPLACE INTO adlist SELECT * FROM OLD.adlist;
DELETE FROM OLD.adlist_by_group WHERE adlist_id NOT IN (SELECT id FROM OLD.adlist);
INSERT OR REPLACE INTO adlist_by_group SELECT * FROM OLD.adlist_by_group;

INSERT OR REPLACE INTO client SELECT * FROM OLD.client;
DELETE FROM OLD.client_by_group WHERE client_id NOT IN (SELECT id FROM OLD.client);
INSERT OR REPLACE INTO client_by_group SELECT * FROM OLD.client_by_group;


CREATE TRIGGER tr_domainlist_add AFTER INSERT ON domainlist
    BEGIN
      INSERT INTO domainlist_by_group (domainlist_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_client_add AFTER INSERT ON client
    BEGIN
      INSERT INTO client_by_group (client_id, group_id) VALUES (NEW.id, 0);
    END;

CREATE TRIGGER tr_adlist_add AFTER INSERT ON adlist
    BEGIN
      INSERT INTO adlist_by_group (adlist_id, group_id) VALUES (NEW.id, 0);
    END;


COMMIT;
