/* contrib/tablelog/tablelog--0.1.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION tablelog" to load this file. \quit

CREATE OR REPLACE FUNCTION get_primary_keys(schema_name TEXT, table_name TEXT)
  RETURNS TEXT[]
AS
$$
DECLARE
  pkeys TEXT[];
BEGIN
    WITH temp AS (
    SELECT
      c.oid relid,
      unnest(c2.conkey) conkey
    FROM
      pg_constraint c2,
      pg_class c,
      pg_namespace n
    WHERE
      c2.conrelid = c.oid
    AND
      c.relnamespace = n.oid
    AND
      n.nspname = schema_name
    AND
      c.relname = table_name
    AND
      c2.contype = 'p'
    )
    SELECT INTO pkeys
      array_agg(attname)
    FROM
      temp t,
      pg_attribute a
    WHERE
      t.relid = a.attrelid
    AND
      t.conkey = a.attnum;

  RETURN pkeys;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION get_unique_keys(schema_name TEXT, table_name TEXT)
  RETURNS TEXT[]
AS
$$
DECLARE
  uniq_keys TEXT[];
BEGIN

    WITH temp2 AS (
    SELECT
      c.oid relid,
      conkey
    FROM
      pg_constraint c2,
      pg_class c,
      pg_namespace n
    WHERE
      c2.conrelid = c.oid
    AND
      c.relnamespace = n.oid
    AND
      n.nspname = schema_name
    AND
      c.relname = table_name
    AND
      contype = 'u'
    ORDER BY
      c2.oid
    LIMIT 1
    ),
    temp AS (
    SELECT
      relid,
      unnest(conkey) conkey
    FROM
      temp2
    )
    SELECT INTO uniq_keys
      array_agg(attname)
    FROM
      temp t,
      pg_attribute a
    WHERE
      t.relid = a.attrelid
    AND
      t.conkey = a.attnum;

  RETURN uniq_keys;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION get_column_names(schema_name TEXT, table_name TEXT)
  RETURNS TEXT[]
AS
$$
DECLARE
  column_names TEXT[];
BEGIN

    WITH temp AS (
    SELECT
      attname
    FROM
      pg_attribute a,
      pg_class c,
      pg_namespace n
    WHERE
      attnum > 0
    AND
      a.attrelid = c.oid
    AND
      c.relname = 't1_u4'
    AND
      c.relnamespace = n.oid
    AND
      n.nspname = 'public'
    ORDER BY
      attnum
    )
    SELECT INTO column_names
      array_agg(attname)
    FROM
      temp;

  RETURN column_names;
END
$$
LANGUAGE 'plpgsql';
