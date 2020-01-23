.timeout 30000

ATTACH DATABASE '/etc/pihole/gravity.db' AS OLD;

BEGIN TRANSACTION;

INSERT OR REPLACE INTO "group" SELECT * FROM OLD."group";
INSERT OR REPLACE INTO domain_audit SELECT * FROM OLD.domain_audit;

INSERT OR REPLACE INTO domainlist SELECT * FROM OLD.domainlist;
INSERT OR REPLACE INTO domainlist_by_group SELECT * FROM OLD.domainlist_by_group;

INSERT OR REPLACE INTO adlist SELECT * FROM OLD.adlist;
INSERT OR REPLACE INTO adlist_by_group SELECT * FROM OLD.adlist_by_group;

INSERT OR REPLACE INTO info SELECT * FROM OLD.info;

INSERT OR REPLACE INTO client SELECT * FROM OLD.client;
INSERT OR REPLACE INTO client_by_group SELECT * FROM OLD.client_by_group;

COMMIT;
