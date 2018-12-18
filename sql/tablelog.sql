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

SELECT get_column_names('public', 't1_u4');  -- {uid,uname}

SELECT get_logging_keys('public', 't1');     -- NULL
SELECT get_logging_keys('public', 't1_u');   -- {uid}
SELECT get_logging_keys('public', 't1_u2');  -- {uid}
SELECT get_logging_keys('public', 't1_u3');  -- {uname}
SELECT get_logging_keys('public', 't1_u4');  -- {uid,uname}
SELECT get_logging_keys('public', 't1_p');   -- {uid}
SELECT get_logging_keys('public', 't1_p2');  -- {uid,uname}
