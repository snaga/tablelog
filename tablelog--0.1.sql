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

CREATE OR REPLACE FUNCTION get_logging_keys(schema_name TEXT, table_name TEXT)
  RETURNS TEXT[]
AS
$$
   SELECT coalesce(get_primary_keys(schema_name, table_name),
                   get_unique_keys(schema_name, table_name));
$$
LANGUAGE SQL;

CREATE TABLE __table_logs__ (
  ts TIMESTAMP NOT NULL,
  txid BIGINT NOT NULL,
  dbuser NAME NOT NULL,
  schemaname NAME NOT NULL,
  tablename NAME NOT NULL,
  event TEXT NOT NULL,
  col_names TEXT[] NOT NULL,
  old_vals TEXT[],
  new_vals TEXT[],
  key_names TEXT[] NOT NULL,
  key_vals TEXT[],
  status SMALLINT NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION tablelog_logging_trigger()
  RETURNS TRIGGER
AS
$$
  //plv8.elog(NOTICE, "TG_ARGV = ", TG_ARGV[0]);

  // ----------------------------
  // 主キーまたはユニークキーを構成するカラム名を取得する
  // ----------------------------
  var key_names = TG_ARGV[0].split(',');
  var key_names_literal = "ARRAY['" + key_names.join("','") + "']";

  //plv8.elog(NOTICE, "key_names_literal = ", key_names_literal);

  // ----------------------------
  // 主キーまたはユニークキーの値をカラム名の順番に配列にする
  //
  // UPDATE/DELETEの場合は、更新前のレコードの値を用いる。
  // INSERTの場合は、更新後（新規作成）のレコードの値を用いる。
  // ----------------------------
  if (typeof OLD !== 'undefined') {
    var key_vals = [];
    key_names.forEach(function(k) {
      key_vals.push(OLD[k]);
    });
    var key_vals_literal = "ARRAY['" + key_vals.join("','") + "']";
  }
  else if (typeof NEW !== 'undefined') {
    var key_vals = [];
    key_names.forEach(function(k) {
      key_vals.push(NEW[k]);
    });
    var key_vals_literal = "ARRAY['" + key_vals.join("','") + "']";
  }

  //plv8.elog(NOTICE, "key_vals_literal = ", key_vals_literal);

  // ----------------------------
  // テーブルの全カラム名を配列にする
  // ----------------------------
  var cols = [];
  if (typeof OLD !== 'undefined') {
    cols = Object.keys(OLD);
  }
  else if (typeof NEW !== 'undefined') {
    cols = Object.keys(NEW);
  }

  //plv8.elog(NOTICE, "cols = ", cols);

  // ----------------------------
  // UPDATEの場合は、更新のあったカラムに絞る
  // ----------------------------
  if (typeof OLD !== 'undefined' && typeof NEW !== 'undefined') {
    var changed_cols = [];
    cols.forEach(function(c) {
      if (OLD[c] !== NEW[c]) {
        changed_cols.push(c);
      }
    });
    cols = changed_cols;
  }

  var col_names_literal = "ARRAY['" + cols.join("','") + "']";

  //plv8.elog(NOTICE, "col_names_literal = ", col_names_literal);

  // ----------------------------------
  // 更新前のレコードの値をカラム名の順番に配列にする
  // ----------------------------------
  if (typeof OLD !== 'undefined') {
    var old_vals = [];
    cols.forEach(function (c) {
      old_vals.push(OLD[c]);
    });
    var old_vals_literal = "ARRAY['" + old_vals.join("','") + "']";
  }
  else {
    var old_vals_literal = 'null';
  }

  //plv8.elog(NOTICE, "old_vals_literal = ", old_vals_literal);

  // ----------------------------------
  // 更新後のレコードの値をカラム名の順番に配列にする
  // ----------------------------------
  if (typeof NEW !== 'undefined') {
    var new_vals = [];
    cols.forEach(function (c) {
      new_vals.push(NEW[c]);
    });
    var new_vals_literal = "ARRAY['" + new_vals.join("','") + "']";
  }
  else {
    var new_vals_literal = 'null';
  }

  //plv8.elog(NOTICE, "new_vals_literal = ", new_vals_literal);

  // ----------------------------------
  // 更新情報をログテーブルに記録する
  // ----------------------------------
  var q = "INSERT INTO __table_logs__ VALUES(clock_timestamp(), txid_current(), current_user, '" + TG_TABLE_SCHEMA+ "', '" + TG_TABLE_NAME + "', '" + TG_OP + "', " + col_names_literal + ", " + old_vals_literal + ", " + new_vals_literal + ", " + key_names_literal + ", " + key_vals_literal + ")";
  //plv8.elog(NOTICE, q);
  
  plv8.execute(q);

  return;
$$
LANGUAGE 'plv8';

CREATE OR REPLACE FUNCTION tablelog_enable_logging(schema_name TEXT, table_name TEXT)
  RETURNS boolean
AS
$$
DECLARE
  trigger_name TEXT;
  schema_table_name TEXT;
  ddl TEXT;
  keys TEXT;
BEGIN
  trigger_name = schema_name || '_' || table_name || '_trigger';
  schema_table_name = schema_name || '.' || table_name;

  keys = array_to_string(get_logging_keys(schema_name, table_name), ',');

  IF keys IS NULL THEN
    RAISE EXCEPTION 'Primary key or unique key not found on the table.';
  END IF;

  ddl = 'CREATE TRIGGER ' || trigger_name || '
           AFTER INSERT OR UPDATE OR DELETE ON ' || schema_table_name || '
           FOR EACH ROW
           EXECUTE PROCEDURE tablelog_logging_trigger(''' || keys || ''')';
  EXECUTE ddl;

  RETURN true;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION tablelog_disable_logging(schema_name TEXT, table_name TEXT)
  RETURNS boolean
AS
$$
DECLARE
  trigger_name TEXT;
  schema_table_name TEXT;
  ddl TEXT;
  keys TEXT;
BEGIN
  trigger_name = schema_name || '_' || table_name || '_trigger';
  schema_table_name = schema_name || '.' || table_name;

  ddl = 'DROP TRIGGER ' || trigger_name || ' ON ' || schema_table_name;
  EXECUTE ddl;

  RETURN true;
END
$$
LANGUAGE 'plpgsql';
