# tablelog

## tablelogについて

tablelogは、テーブルへの更新処理（INSERT/UPDATE/DELETE）をログとして記
録するためのPostgreSQLの拡張モジュール（extension）です。

tablelogは、各テーブルに設定したトリガを使って、当該テーブルへの更新処
理を記録用のテーブルに保存します。

tablelogを使うことによって、テーブルへの更新内容を後から確認、または再
生することでテーブルの複製やデータベースの移行に利用することができます。


## 稼働条件

tablelogが稼働する条件は以下の通りです。

* PostgreSQL 9.4以降
* PL/Perl
* 対象となるテーブルに主キーまたはユニーク制約が作成されていること

tablelogでは、トリガをPL/Perlで実装しています。

これは、トリガで必要となる機能の一部をPL/pgSQLでは実装できないこと、お
よびPL/PerlであればAmazonのRDS for PostgreSQLで利用できるためです。


## インストール方法

スタンドアロンのPostgreSQLにインストールする場合は、通常のextensionと同
じようにインストールして、 `CREATE EXTENSION` してください。

```
env USE_PGXS=1 make install
psql -c 'create extension plperl' dbname
psql -c 'create extension tablelog' dbname
````

DBaaSで利用する場合には、 `tablelog--X.X.sql` ファイルを実行して必要な
SQL関数やオブジェクトを直接作成してください。

その際、 `\echo` から始まる行はコメントアウトしておいてください。

```
vi tablelog--X.X.sql
psql -c 'create extension plperl' dbname
psql -f tablelog--X.X.sql dbname
```


## 作成されるSQL関数とオブジェクト

ユーザが直接参照する、または目にするSQL関数とオブジェクトは以下の通りで
す。

* tablelog_enable_logging 関数 - 更新処理のロギングを開始する
* tablelog_disable_logging 関数 - 更新処理のロギングを終了する
* tablelog_logging_trigger 関数 - 各テーブルに設定されるロギング用トリガ
* __table_logs__ テーブル - 更新処理が記録されるログテーブル


## 使い方

テーブルのロギングを開始する場合には、スキーマ名とテーブル名を引数に
与えて tablelog_enable_logging 関数を実行します。

```
dbname=# SELECT tablelog_enable_logging('public', 't1');
 tablelog_enable_logging
-------------------------
 t
(1 row)

dbname=# 
```

テーブルに主キー制約またはユニーク制約が無い場合には以下のようにエラーになります。

```
dbname=# SELECT tablelog_enable_logging('public', 't1');
ERROR:  Primary key or unique key not found on the table.
CONTEXT:  PL/pgSQL function tablelog_enable_logging(text,text) line 14 at RAISE

dbname=# 
```

設定に成功すると、以下のようにテーブルにトリガが設定されます。

```
dbname=# \d+ t1
                                    Table "public.t1"
 Column |  Type   | Collation | Nullable | Default | Storage  | Stats target | Description
--------+---------+-----------+----------+---------+----------+--------------+-------------
 uid    | integer |           |          |         | plain    |              |
 uname  | text    |           |          |         | extended |              |
Indexes:
    "t1_uid_uname_key" UNIQUE CONSTRAINT, btree (uid, uname)
Triggers:
    public_t1_trigger AFTER INSERT OR DELETE OR UPDATE ON t1 FOR EACH ROW EXECUTE PROCEDURE tablelog_logging_trigger('uid,uname')
```

この状態でテーブルにINSERT/UPDATE/DELETEを行うと、それぞれ以下のように記録が残ります。

```
dbname=# BEGIN;
BEGIN
dbname=# INSERT INTO t1 VALUES (1, 'user1');
INSERT 1
dbname=# UPDATE t1 SET uname = 'user01';
UPDATE 1
dbname=# DELETE FROM t1;
DELETE 1
dbname=# COMMIT;
COMMIT
dbname=# SELECT * FROM __table_logs__;
               ts                | txid | dbuser | schemaname | tablename | event  |  col_names  |  old_vals  | new_vals  |  key_names  |  key_vals  | status
---------------------------------+------+--------+------------+-----------+--------+-------------+------------+-----------+-------------+------------+--------
 Wed Dec 19 20:39:33.365696 2018 | 4736 | snaga  | public     | t1        | INSERT | {uname,uid} |            | {user1,1} | {uid,uname} |            |      0
 Wed Dec 19 20:39:33.366558 2018 | 4736 | snaga  | public     | t1        | UPDATE | {uname}     | {user1}    | {user01}  | {uid,uname} | {1,user1}  |      0
 Wed Dec 19 20:39:33.367174 2018 | 4736 | snaga  | public     | t1        | DELETE | {uname,uid} | {user01,1} |           | {uid,uname} | {1,user01} |      0
(3 rows)

```

テーブルのロギングを停止するには tablelog_disable_logging 関数を使います。

```
dbname=# SELECT tablelog_disable_logging('public', 't1');
 tablelog_disable_logging
--------------------------
 t
(1 row)

dbname=# 
```


## ログテーブルの構造

ログテーブルの各カラムは以下の通りです。

| カラム名   | データ型                    |   概要             | 備考                                                    |
|------------|-----------------------------|--------------------|---------------------------------------------------------|
| ts         | timestamp without time zone | タイムスタンプ     | 当該のイベントが記録された時刻（clock_timestamp()の値） |
| txid       | bigint                      | トランザクションID | トランザクションID（単調増加）                          |
| dbuser     | name                        | データベースユーザ | 更新処理を行ったデータベースユーザ（current_userの値）  |
| schemaname | name                        | スキーマ名         | 更新されたテーブルのスキーマ名                          |
| tablename  | name                        | テーブル名         | 更新されたテーブルのテーブル名                          |
| event      | text                        | イベント名         | 更新処理の種別（INSERT/UPDATE/DELETEのいずれか）        |
| col_names  | text[]                      | カラム名リスト     | 更新されたカラム名のリスト                              |
| old_vals   | text[]                      | 更新前の値リスト   | 更新される前の値のリスト。INSERT時はNULL。              |
| new_vals   | text[]                      | 更新後の値リスト   | 更新された後の値のリスト。DELETE字はNULL。              |
| key_names  | text[]                      | キーカラムリスト   | レコードを特定する主キー/ユニークキーのカラム名リスト   |
| key_vals   | text[]                      | キー値リスト       | レコードを特定する主キー/ユニークキーの値リスト         |
| status     | smallint                    |  ログのステータス  | 作成直後は'0'。それ以外はユーザ定義。                   |


## 開発者

Satoshi Nagayasu <snaga _at_ uptime _dot_ jp>


EOF
