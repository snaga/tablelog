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
  key_vals TEXT[]
);

CREATE OR REPLACE FUNCTION tablelog_logging_trigger()
  RETURNS TRIGGER
AS
$$
  # ----------------------------
  # 主キーまたはユニークキーを構成するカラム名を取得する
  # ----------------------------
  @key_names = split(/,/, ${$_TD->{args}}[0]);
  $key_names_literal = "ARRAY['" . join("','", @key_names) . "']";

  # ----------------------------
  # 主キーまたはユニークキーの値をカラム名の順番に配列にする
  # ----------------------------
  if (defined($_TD->{old})) {
    @key_vals = ();
    foreach (@key_names) {
      push(@key_vals, $_TD->{old}{$_});
    }
    $key_vals_literal = "ARRAY['" . join("','", @key_vals) . "']";
  }
  else {
    $key_vals_literal = 'null';
  }

  # ----------------------------
  # テーブルの全カラム名を配列にする
  # ----------------------------
  @cols = ();
  if (defined($_TD->{old})) {
    push(@cols, keys $_TD->{old});
  }
  elsif (defined($_TD->{new})) {
    push(@cols, keys $_TD->{new});
  }
  $col_names_literal = "ARRAY['" . join("','", @cols) . "']";

  # ----------------------------------
  # 更新前のレコードの値をカラム名の順番に配列にする
  # ----------------------------------
  if (defined($_TD->{old})) {
    @old_vals = ();
    foreach (@cols) {
      push(@old_vals, $_TD->{old}{$_});
    }
    $old_vals_literal = "ARRAY['" . join("','", @old_vals) . "']";
  }
  else {
    $old_vals_literal = 'null';
  }

  # ----------------------------------
  # 更新後のレコードの値をカラム名の順番に配列にする
  # ----------------------------------
  if (defined($_TD->{new})) {
    @new_vals = ();
    foreach (@cols) {
      push(@new_vals, $_TD->{new}{$_});
    }
    $new_vals_literal = "ARRAY['" . join("','", @new_vals) . "']";
  }
  else {
    $new_vals_literal = 'null';
  }

  # ----------------------------------
  # 更新情報をログテーブルに記録する
  # ----------------------------------
  $q = "INSERT INTO __table_logs__ VALUES(clock_timestamp(), txid_current(), current_user, '" . $_TD->{table_schema} . "', '" . $_TD->{table_name} . "', '" . $_TD->{event} . "', " . $col_names_literal . ", " . $old_vals_literal . ", " . $new_vals_literal . ", " . $key_names_literal . ", " . $key_vals_literal . ")";
  elog(DEBUG, $q);
  
  $rs = spi_exec_query($q);

  return;
$$
LANGUAGE 'plperl';
