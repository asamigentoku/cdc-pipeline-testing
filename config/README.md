# Connector設定の説明

このディレクトリには、Kafka Connect REST APIへ登録するConnector設定があります。

- `source.json`: PostgreSQLの変更をKafkaへ送るDebezium Source Connector
- `sink.json`: KafkaのイベントをBigQueryへ送るBigQuery Sink Connector

JSON仕様はコメントをサポートしません。これらのファイルへ`//`や`/* ... */`を追加すると、READMEに記載した`curl.exe`コマンドで登録できなくなるため、各項目の説明をこのファイルにまとめています。

## source.json

| 設定 | 現在値 | 説明 |
| --- | --- | --- |
| `name` | `postgres-source` | Kafka Connect内でConnectorを一意に識別する名前です。同名のConnectorは重複登録できません。 |
| `connector.class` | `io.debezium.connector.postgresql.PostgresConnector` | PostgreSQL用のDebezium Source Connectorを指定します。 |
| `tasks.max` | `1` | 作成できるタスク数の上限です。Debezium PostgreSQL Connectorは常に単一タスクで動作します。 |
| `database.hostname` | `postgres` | 接続先PostgreSQLのホスト名です。Docker Composeのサービス名で名前解決します。 |
| `database.port` | `5432` | コンテナ間通信で使用するPostgreSQLのポートです。ホスト側の`5433`ではありません。 |
| `database.user` | `postgres` | PostgreSQLへの接続と論理レプリケーションに使用するユーザーです。 |
| `database.password` | `postgres` | 上記ユーザーのパスワードです。ローカル検証用の値であり、本番環境ではSecret管理へ移します。 |
| `database.dbname` | `appdb` | 変更を取得するPostgreSQLデータベースです。 |
| `topic.prefix` | `cdc` | 作成するKafkaトピック名の先頭部分です。現在の対象は`cdc.public.orders`になります。運用開始後の変更は別トピックを作る原因になるため注意が必要です。 |
| `plugin.name` | `pgoutput` | PostgreSQL標準の論理デコードプラグインを使用します。Compose側の`wal_level=logical`が必要です。 |
| `slot.name` | `cdc_orders_slot` | WALの読み取り位置を保持する論理レプリケーションスロット名です。同じPostgreSQL内の別Connectorと重複させません。 |
| `publication.autocreate.mode` | `filtered` | `table.include.list`に一致するテーブルを含むPublicationをDebeziumが自動作成・更新します。Connectorユーザーには必要な権限が必要です。 |
| `table.include.list` | `public.orders` | CDC対象を`public.orders`だけに限定します。複数指定する場合はカンマで区切ります。 |
| `snapshot.mode` | `initial` | 保存済みオフセットがない初回起動時に既存行をスナップショットし、その後WALから継続的に変更を取得します。 |
| `transforms` | `unwrap` | 適用するSingle Message Transform（SMT）へ`unwrap`という別名を付けます。 |
| `transforms.unwrap.type` | `io.debezium.transforms.ExtractNewRecordState` | Debezium固有の`before`、`after`、`source`を持つイベントを、変更後の行データ中心の平坦な形式へ変換します。 |
| `transforms.unwrap.delete.tombstone.handling.mode` | `rewrite` | DELETEイベントを破棄せず、削除前の行データに`__deleted=true`を追加した形式へ変換します。 |
| `transforms.unwrap.add.fields` | `op,table,source.ts_ms` | 平坦化後の値へ操作種別、テーブル名、変更元時刻を追加します。実際のフィールド名には`__op`、`__table`、`__source_ts_ms`のように接頭辞が付きます。 |

### 対象テーブルを増やす場合

例えば、`orders`、`payments`、`audit_logs`を取得する場合は次のように変更します。

```json
"table.include.list": "public.orders,public.payments,public.audit_logs"
```

対象テーブルごとに、通常は`cdc.public.orders`、`cdc.public.payments`のようなKafkaトピックが作成されます。Sink Connector側の`topics`も合わせて変更してください。

## sink.json

| 設定 | 現在値 | 説明 |
| --- | --- | --- |
| `name` | `bigquery-sink` | Kafka Connect内でSink Connectorを一意に識別する名前です。 |
| `connector.class` | `com.wepay.kafka.connect.bigquery.BigQuerySinkConnector` | KafkaのレコードをBigQueryへ書き込むConnectorを指定します。 |
| `tasks.max` | `1` | 並列実行するSinkタスク数の上限です。この検証環境では1タスクで処理します。 |
| `topics` | `cdc.public.orders` | BigQueryへ転送するKafkaトピックです。複数指定する場合はカンマで区切ります。 |
| `project` | `REPLACE_WITH_GCP_PROJECT_ID` | 書き込み先のGCPプロジェクトIDです。起動前に実際のIDへ置き換えます。 |
| `defaultDataset` | `cdc` | 書き込み先BigQueryデータセットです。事前に作成しておきます。 |
| `keySource` | `APPLICATION_DEFAULT` | サービスアカウントのJSONキーではなく、Kafka Connectコンテナに渡したApplication Default Credentialsを使用します。`keyfile`は指定しません。 |
| `autoCreateTables` | `true` | 対応するBigQueryテーブルが存在しない場合に自動作成します。データセット自体は事前作成が必要です。 |
| `sanitizeTopics` | `true` | Kafkaトピック名をBigQueryで使用可能なテーブル名へ変換します。例えば、ドットなどの使用できない文字がアンダースコアへ置換されます。 |
| `allowNewBigQueryFields` | `true` | Kafka側のスキーマへフィールドが追加された場合、BigQueryテーブルにも新しいNULL許容フィールドを追加できるようにします。 |
| `allowBigQueryRequiredFieldRelaxation` | `true` | スキーマ変更時にBigQueryの`REQUIRED`フィールドを`NULLABLE`へ緩和できるようにします。逆方向には変更しません。 |

## Docker Compose側の関連設定

| 設定 | 説明 |
| --- | --- |
| `wal_level=logical` | PostgreSQLのWALを論理デコード可能な形式にします。DebeziumによるCDCの必須設定です。 |
| `max_replication_slots=10` | 同時に保持できる論理・物理レプリケーションスロット数の上限です。 |
| `max_wal_senders=10` | WALを送信できる同時接続数の上限です。 |
| `GOOGLE_APPLICATION_CREDENTIALS=/gcp/adc.json` | Google認証ライブラリへ、コンテナ内のADCファイル位置を通知します。 |
| `${APPDATA}/gcloud/application_default_credentials.json` | Windowsホストで`gcloud auth application-default login`が作成したADCファイルです。コンテナへ読み取り専用でマウントします。 |

その他のCompose設定には、`docker-compose.yml`内に各項目の説明コメントを記載しています。
