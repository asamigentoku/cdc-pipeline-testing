# cdc-pipeline-testing

PostgreSQLの`orders`テーブルに発生した変更をDebeziumで取得し、Kafkaを経由してBigQueryへ連携するCDC（Change Data Capture）の検証環境です。

```text
PostgreSQL → Debezium / Kafka Connect → Kafka → BigQuery Sink → BigQuery
                                        ↕
                                   Kafbat UI
```

## 必要なもの

- Docker Desktop（Docker Compose v2を含む）
- Google Cloud CLI（`gcloud`コマンド）
- BigQueryを利用できるGCPプロジェクト
- BigQueryへの書き込み権限を持つGoogleアカウント
- PowerShell

Dockerが利用可能か、次のコマンドで確認します。

```powershell
docker --version
docker compose version
```

## 1. GCPの設定

この環境ではサービスアカウントのJSONキーを作成せず、ローカル開発用のApplication Default Credentials（ADC）を使用します。

### 1-1. プロジェクトの選択とADCログイン

`YOUR_GCP_PROJECT_ID`を使用するGCPプロジェクトIDに置き換えて実行します。

```powershell
gcloud config set project YOUR_GCP_PROJECT_ID
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_GCP_PROJECT_ID
```

ブラウザでGoogleアカウントへログインすると、Windowsでは通常、次の場所にADCファイルが作成されます。

```text
%APPDATA%\gcloud\application_default_credentials.json
```

認証できることを確認します。表示されたアクセストークンは第三者へ共有しないでください。

```powershell
gcloud auth application-default print-access-token
```

Docker ComposeはこのADCファイルをKafka Connectコンテナの`/gcp/adc.json`へ読み取り専用でマウントします。ADCファイルには更新トークンが含まれるため、コピーしたりGitへコミットしたりしないでください。

### 1-2. BigQueryの準備

ログインしたGoogleアカウントには、少なくとも次の権限が必要です。

- 対象の`cdc`データセットに対するBigQuery Data Editor
- 対象プロジェクトに対するBigQuery Job User

BigQueryに`cdc`データセットを作成します。東京リージョンを使用する例は次のとおりです。既存データの配置先に合わせてロケーションを変更してください。

```powershell
bq --location=asia-northeast1 mk --dataset YOUR_GCP_PROJECT_ID:cdc
```

### 1-3. Sink ConnectorのプロジェクトID

`config/sink.json`のプロジェクトIDを書き換えます。

```json
"project": "REPLACE_WITH_GCP_PROJECT_ID"
```

例えば、GCPプロジェクトIDが`my-cdc-project`の場合は次のようにします。

```json
"project": "my-cdc-project"
```

`keySource`は`APPLICATION_DEFAULT`に設定済みです。サービスアカウントの`keyfile`は使用しません。

## 2. コンテナの起動

プロジェクトのルートディレクトリで、イメージをビルドして全サービスを起動します。

```powershell
docker compose up -d --build
```

Kafka Connectのイメージ構築時にDebezium PostgreSQL ConnectorとBigQuery Sink Connectorをダウンロードするため、初回は時間がかかることがあります。

起動状態を確認します。

```powershell
docker compose ps
```

Kafbat UIは次のURLで開けます。

```text
http://localhost:8080
```

Kafbat UIから、Kafkaのトピック、イベント、パーティション、Consumer Group、およびKafka Connectの状態を確認できます。

Kafka Connectが起動しない場合はログを確認します。

```powershell
docker compose logs -f connect
```

## 3. コネクターの登録

Kafka Connect REST APIが応答することを確認します。

```powershell
curl.exe http://localhost:8083/
```

PostgreSQLから変更を取得するSource Connectorを登録します。

```powershell
curl.exe -X POST `
  -H "Content-Type: application/json" `
  --data-binary "@config/source.json" `
  http://localhost:8083/connectors
```

KafkaのデータをBigQueryへ書き込むSink Connectorを登録します。

```powershell
curl.exe -X POST `
  -H "Content-Type: application/json" `
  --data-binary "@config/sink.json" `
  http://localhost:8083/connectors
```

登録済みコネクターの一覧を確認します。

```powershell
curl.exe http://localhost:8083/connectors
```

各コネクターの状態を確認します。`connector`と`tasks`の`state`が`RUNNING`になれば準備完了です。

```powershell
curl.exe http://localhost:8083/connectors/postgres-source/status
curl.exe http://localhost:8083/connectors/bigquery-sink/status
```

## 4. CDCの動作確認

PostgreSQLの`orders`テーブルへテストデータを追加します。

```powershell
docker compose exec postgres psql -U postgres -d appdb -c "INSERT INTO orders (user_id, amount, status) VALUES (1001, 2500, 'created');"
```

登録されたデータを確認します。

```powershell
docker compose exec postgres psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"
```

Kafkaの`cdc.public.orders`トピックにイベントが届いていることをKafbat UIで確認します。

1. ブラウザで`http://localhost:8080`を開きます。
2. `local`クラスタを選択します。
3. 左側の`Topics`を開きます。
4. `cdc.public.orders`を選択します。
5. `Messages`タブを開き、イベントを確認します。

画面にはINSERT、UPDATE、DELETEによってKafkaへ送られたJSONイベントが表示されます。Kafka Connectのコネクター状態は、左側の`Kafka Connect`から確認できます。

コマンドラインでイベントを確認する場合は、次のコマンドを使用します。

```powershell
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh `
  --bootstrap-server kafka:29092 `
  --topic cdc.public.orders `
  --from-beginning `
  --max-messages 1
```

最後に、BigQueryの`cdc`データセット内に作成されたテーブルとデータを確認してください。反映には少し時間がかかる場合があります。

更新・削除イベントも次のコマンドで確認できます。

```powershell
# 更新
docker compose exec postgres psql -U postgres -d appdb -c "UPDATE orders SET status = 'paid' WHERE id = 1;"

# 削除
docker compose exec postgres psql -U postgres -d appdb -c "DELETE FROM orders WHERE id = 1;"
```

## 停止と再起動

コンテナを停止します。データは名前付きボリュームに保持されます。

```powershell
docker compose down
```

再度起動する場合は次を実行します。

```powershell
docker compose up -d
```

## データを含めて初期化

次のコマンドはコンテナに加えてPostgreSQLとKafkaの名前付きボリュームも削除します。保存済みデータとCDCの読み取り位置が失われるため注意してください。

```powershell
docker compose down -v
docker compose up -d --build
```

初期化後は「3. コネクターの登録」から再実行します。

## よく使う確認コマンド

```powershell
# 全サービスの状態
docker compose ps

# 全サービスのログ
docker compose logs -f

# Kafka Connectのログ
docker compose logs -f connect

# PostgreSQLのログ
docker compose logs -f postgres

# Kafkaのログ
docker compose logs -f kafka

# Kafbat UIのログ
docker compose logs -f kafka-ui

# 登録済みコネクター
curl.exe http://localhost:8083/connectors
```

コネクターが`FAILED`の場合は、ステータスAPIの`trace`とKafka Connectのログを確認してください。特にBigQuery Sinkでは、GCPプロジェクトID、ADCファイル、ログインしたGoogleアカウントのIAM権限、`cdc`データセットの有無を確認します。
