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
  //
  // ここで取得するカラム名は、テーブルにトリガを設定した際に
  // トリガ関数への引数として明示的に設定したものを使う。
  // ----------------------------
  var key_names = TG_ARGV[0].split(',');
  var key_names_literal = "ARRAY['" + key_names.join("','") + "']";

  //plv8.elog(NOTICE, "key_names_literal = ", key_names_literal);

  function array_to_literal(a) {
    var b = [];
    a.forEach(function(s) {
      if (typeof s === 'string') {
        b.push(s.replace("'", "''"));
      }
      else {
        b.push(s);
      }
    });
    return "ARRAY['" + b.join("','") + "']"
  }

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
    var key_vals_literal = array_to_literal(key_vals);
  }
  else if (typeof NEW !== 'undefined') {
    var key_vals = [];
    key_names.forEach(function(k) {
      key_vals.push(NEW[k]);
    });
    var key_vals_literal = array_to_literal(key_vals);
  }

  //plv8.elog(NOTICE, "key_vals_literal = ", key_vals_literal);

  // ----------------------------
  // テーブルの全カラム名を配列にする
  //
  // UPDATE/DELETEの場合は、更新前のレコードから取得する。
  // INSERTの場合は、更新後（新規作成）のレコードから取得する。
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
  // UPDATEの場合は、値が変更されたカラムのみをロギング対象とする
  // ----------------------------
  if (typeof OLD !== 'undefined' && typeof NEW !== 'undefined') {
    var changed_cols = [];
    cols.forEach(function(c) {
      if (OLD[c] !== NEW[c]) {
        changed_cols.push(c);
      }
    });
    cols = changed_cols;
    if (changed_cols.length == 0) {
       // UPDATEでどのカラムの値も変わらない場合にはログは記録しない。
       //rs = plv8.execute('SELECT txid_current()');
       //plv8.elog(NOTICE, "Updated, but nothing changed: txid = ", rs[0]['txid_current']);
       return;
    }
  }

  var col_names_literal = "ARRAY['" + cols.join("','") + "']";

  //plv8.elog(NOTICE, "col_names_literal = ", col_names_literal);

  // ----------------------------------
  // 更新前のレコードの値をカラム名の順番に配列にする
  //
  // UPDATE/DELETEの場合のみ記録される。
  // INSERTの場合はNULLとなる。
  // ----------------------------------
  if (typeof OLD !== 'undefined') {
    var old_vals = [];
    cols.forEach(function (c) {
      old_vals.push(OLD[c]);
    });
    var old_vals_literal = array_to_literal(old_vals);
  }
  else {
    var old_vals_literal = 'null';
  }

  //plv8.elog(NOTICE, "old_vals_literal = ", old_vals_literal);

  // ----------------------------------
  // 更新後のレコードの値をカラム名の順番に配列にする
  //
  // INSERT/UPDATEの場合のみ記録される。
  // DELETEの場合はNULLとなる。
  // ----------------------------------
  if (typeof NEW !== 'undefined') {
    var new_vals = [];
    cols.forEach(function (c) {
      new_vals.push(NEW[c]);
    });
    var new_vals_literal = array_to_literal(new_vals);
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

CREATE OR REPLACE FUNCTION tablelog_replay_logs()
  RETURNS SETOF TEXT
AS
$$
DECLARE
  r RECORD;
  r2 RECORD;
  query TEXT;
  schema_table_name TEXT;
  _key_clause TEXT;
  _set_clause TEXT;
  _columns_clause TEXT;
  _values_clause TEXT;
BEGIN
  RETURN NEXT 'BEGIN;';

  FOR r IN
    SELECT
      to_char(ts, 'YYYY-MM-DD HH24:MI:SS.US') ts,
      txid,
      event,
      schemaname, tablename,
      key_names, key_vals,
      col_names, old_vals, new_vals
    FROM
      __table_logs__
    WHERE
      status = 0
    ORDER BY
      ts
    LOOP

    query = '/* ' || r.txid || ', ' || r.ts || ' */ ';
    schema_table_name = r.schemaname || '.' || r.tablename;

    IF r.event = 'INSERT' THEN
      -- INSERTの場合はカラム名と各カラムの値をカンマ区切りの文字列に
      -- 組み立てる。
      _columns_clause = '';
      _values_clause = '';
      FOR r2 IN
        SELECT unnest(r.col_names) col_name,
               unnest(r.new_vals) new_val
        LOOP

        IF length(_columns_clause) > 0 THEN
          _columns_clause = _columns_clause || ',';
          _values_clause = _values_clause || ',';
        END IF;

        _columns_clause = _columns_clause || r2.col_name;
        _values_clause = _values_clause || '''' || r2.new_val || '''';
      END LOOP;

      query = query || r.event || ' ' || schema_table_name || ' (' || _columns_clause || ') VALUES (' || _values_clause || ')';

    ELSIF r.event = 'UPDATE' THEN
      -- UPDATEの場合はWHERE句でキーを指定する必要があるため、
      -- その条件式を組み立てる。
      _key_clause = '';
      FOR r2 IN
        SELECT unnest(r.key_names) key_name,
               unnest(r.key_vals) key_val
        LOOP

        IF length(_key_clause) > 0 THEN
          _key_clause = _key_clause || ' AND ';
        END IF;

        _key_clause = _key_clause || r2.key_name || ' = ''' || r2.key_val || '''';
      END LOOP;

      -- UPDATEの場合は、値を更新するためのSET句を組み立てる。
      _set_clause = '';
      FOR r2 IN
        SELECT unnest(r.col_names) col_name,
               unnest(r.new_vals) new_val
        LOOP

        IF length(_set_clause) > 0 THEN
          _set_clause = _set_clause || ',';
        END IF;

        _set_clause = _set_clause || r2.col_name || ' = ''' || r2.new_val || '''';
      END LOOP;

      query = query || r.event || ' ' || schema_table_name || ' SET ' || _set_clause || ' WHERE ' || _key_clause;

    ELSIF r.event = 'DELETE' THEN
      -- DELETEの場合はWHERE句でキーを指定する必要があるため、
      -- その条件式を組み立てる。
      _key_clause = '';
      FOR r2 IN
        SELECT unnest(r.key_names) key_name,
               unnest(r.key_vals) key_val
        LOOP

        IF length(_key_clause) > 0 THEN
          _key_clause = _key_clause || ' AND ';
        END IF;

        _key_clause = _key_clause || r2.key_name || ' = ''' || r2.key_val || '''';
      END LOOP;

      query = query || r.event || ' FROM ' || schema_table_name || ' WHERE ' || _key_clause;
    END IF;
    RETURN NEXT query || ';';

  END LOOP;
  RETURN NEXT 'COMMIT;';

  RETURN;
END
$$
LANGUAGE 'plpgsql';
