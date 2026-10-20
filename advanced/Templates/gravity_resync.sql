.timeout 30000

PRAGMA foreign_keys=OFF;

ATTACH DATABASE '/etc/pihole/gravity.db' AS OLD;

BEGIN TRANSACTION;

DROP TRIGGER tr_domainlist_add;
DROP TRIGGER tr_client_add;
DROP TRIGGER tr_adlist_add;

-- What this run found out about each list, kept for lists still at the same address
CREATE TEMP TABLE adlist_run AS SELECT id, address, type, date_updated, number, invalid_domains, status, abp_entries FROM main.adlist;

DELETE FROM "group";
INSERT OR REPLACE INTO "group" SELECT * FROM OLD."group";

DELETE FROM domainlist;
INSERT INTO domainlist SELECT * FROM OLD.domainlist;
DELETE FROM domainlist_by_group;
INSERT INTO domainlist_by_group SELECT * FROM OLD.domainlist_by_group WHERE domainlist_id IN (SELECT id FROM domainlist);

DELETE FROM adlist;
INSERT INTO adlist SELECT * FROM OLD.adlist;
DELETE FROM adlist_by_group;
INSERT INTO adlist_by_group SELECT * FROM OLD.adlist_by_group WHERE adlist_id IN (SELECT id FROM adlist);
UPDATE adlist SET (date_updated, number, invalid_domains, status, abp_entries) =
    (SELECT r.date_updated, r.number, r.invalid_domains, r.status, r.abp_entries FROM adlist_run r WHERE r.id = adlist.id)
    WHERE EXISTS (SELECT 1 FROM adlist_run r WHERE r.id = adlist.id AND r.address = adlist.address AND r.type = adlist.type);

DELETE FROM client;
INSERT INTO client SELECT * FROM OLD.client;
DELETE FROM client_by_group;
INSERT INTO client_by_group SELECT * FROM OLD.client_by_group WHERE client_id IN (SELECT id FROM client);


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
