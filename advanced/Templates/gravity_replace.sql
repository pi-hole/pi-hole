.timeout 30000

BEGIN TRANSACTION;

PRAGMA legacy_alter_table=ON;
ALTER TABLE gravity RENAME TO gravity_old;
ALTER TABLE gravity_temp RENAME TO gravity;
PRAGMA legacy_alter_table=OFF;

DROP TABLE gravity_old;

COMMIT;
