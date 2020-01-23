.timeout 30000

BEGIN TRANSACTION;

DROP TABLE IF EXISTS gravity_temp;

CREATE TABLE gravity_temp
(
	domain TEXT NOT NULL,
	adlist_id INTEGER NOT NULL REFERENCES adlist (id),
	PRIMARY KEY(domain, adlist_id)
);

COMMIT;
