.timeout 30000

BEGIN TRANSACTION;

UPDATE info SET value = 2 WHERE property = 'version';

COMMIT;
