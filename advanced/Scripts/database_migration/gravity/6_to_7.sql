.timeout 30000

PRAGMA FOREIGN_KEYS=OFF;

BEGIN TRANSACTION;

INSERT OR REPLACE INTO "group" (id,enabled,name) VALUES (0,1,'Unassociated');

INSERT INTO domainlist_by_group (domainlist_id, group_id) SELECT id, 0 FROM domainlist;
INSERT INTO client_by_group (client_id, group_id) SELECT id, 0 FROM client;
INSERT INTO adlist_by_group (adlist_id, group_id) SELECT id, 0 FROM adlist;

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

CREATE TRIGGER tr_group_zero AFTER DELETE ON "group"
    BEGIN
      INSERT OR REPLACE INTO "group" (id,enabled,name) VALUES (0,1,'Unassociated');
    END;

UPDATE info SET value = 7 WHERE property = 'version';

COMMIT;
