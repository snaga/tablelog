CREATE EXTENSION tablelog;

DROP TABLE IF EXISTS t1;
DROP TABLE IF EXISTS t1_u;
DROP TABLE IF EXISTS t1_u2;
DROP TABLE IF EXISTS t1_p;
DROP TABLE IF EXISTS t1_p2;

CREATE TABLE t1 (
  uid integer,
  uname text
);

CREATE TABLE t1_u (
  uid integer unique,
  uname text
);

CREATE TABLE t1_u2 (
  uid integer unique,
  uname text unique
);

CREATE TABLE t1_u3 (
  uid integer,
  uname text unique
);

CREATE TABLE t1_u4 (
  uid integer,
  uname text,
  unique(uid, uname)
);

CREATE TABLE t1_p (
  uid integer primary key,
  uname text
);

CREATE TABLE t1_p2 (
  uid integer,
  uname text,
  primary key(uid,uname)
);

SELECT get_primary_keys('public', 't1');     -- NULL
SELECT get_primary_keys('public', 't1_u');   -- NULL
SELECT get_primary_keys('public', 't1_u2');  -- NULL
SELECT get_primary_keys('public', 't1_p');   -- {uid}
SELECT get_primary_keys('public', 't1_p2');  -- {uid,uname}

SELECT get_unique_keys('public', 't1');     -- NULL
SELECT get_unique_keys('public', 't1_u');   -- {uid}
SELECT get_unique_keys('public', 't1_u2');  -- {uid}
SELECT get_unique_keys('public', 't1_u3');  -- {uname}
SELECT get_unique_keys('public', 't1_u4');  -- {uid,uname}
SELECT get_unique_keys('public', 't1_p');   -- NULL
SELECT get_unique_keys('public', 't1_p2');  -- NULL

SELECT get_logging_keys('public', 't1');     -- NULL
SELECT get_logging_keys('public', 't1_u');   -- {uid}
SELECT get_logging_keys('public', 't1_u2');  -- {uid}
SELECT get_logging_keys('public', 't1_u3');  -- {uname}
SELECT get_logging_keys('public', 't1_u4');  -- {uid,uname}
SELECT get_logging_keys('public', 't1_p');   -- {uid}
SELECT get_logging_keys('public', 't1_p2');  -- {uid,uname}


CREATE TRIGGER public_t1_u_logging_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.t1_u
  FOR EACH ROW EXECUTE PROCEDURE tablelog_logging_trigger('uid');

CREATE TRIGGER public_t1_u4_logging_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.t1_u4
  FOR EACH ROW EXECUTE PROCEDURE tablelog_logging_trigger('uid,uname');

BEGIN;
INSERT INTO t1_u VALUES (1, 'user1');
UPDATE t1_u SET uname = 'user01';
DELETE FROM t1_u;
COMMIT;

BEGIN;
INSERT INTO t1_u4 VALUES (1, 'user1');
UPDATE t1_u4 SET uname = 'user01';
DELETE FROM t1_u4;
COMMIT;

DROP TRIGGER public_t1_u_logging_trigger ON public.t1_u;
DROP TRIGGER public_t1_u4_logging_trigger ON public.t1_u4;

\d t1_u
\d t1_u4

SELECT
  schemaname,
  tablename,
  event,
  col_names,
  old_vals,
  new_vals,
  key_names,
  key_vals,
  status
FROM
  __table_logs__
ORDER BY
  txid, ts;

TRUNCATE TABLE __table_logs__;

SELECT
  schemaname,
  tablename,
  event,
  col_names,
  old_vals,
  new_vals,
  key_names,
  key_vals,
  status
FROM
  __table_logs__
ORDER BY
  txid, ts;

INSERT INTO t1_u4 VALUES (1, 'user1');

SELECT
  schemaname,
  tablename,
  event,
  col_names,
  old_vals,
  new_vals,
  key_names,
  key_vals,
  status
FROM
  __table_logs__
ORDER BY
  txid, ts;

SELECT
  tablelog_enable_logging('public', 't1_u4');

UPDATE t1_u4 SET uname = 'user01';

SELECT
  schemaname,
  tablename,
  event,
  col_names,
  old_vals,
  new_vals,
  key_names,
  key_vals,
  status
FROM
  __table_logs__
ORDER BY
  txid, ts;

SELECT
  tablelog_disable_logging('public', 't1_u4');

DELETE FROM t1_u4;

SELECT
  schemaname,
  tablename,
  event,
  col_names,
  old_vals,
  new_vals,
  key_names,
  key_vals,
  status
FROM
  __table_logs__
ORDER BY
  txid, ts;

SELECT
  tablelog_enable_logging('public', 't1');
