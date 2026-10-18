
# Kafka Connect 7.9.0を実行環境として使用
FROM confluentinc/cp-kafka-connect:7.9.0

# Connectorをインストールするため、一時的にrootユーザーへ切り替え
USER root

# PostgreSQL CDC用のDebezium ConnectorとBigQuery転送用のSink Connectorをインストール
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest \
 && confluent-hub install --no-prompt wepay/kafka-connect-bigquery:latest

# 実行時は権限を制限したKafka Connect標準ユーザーへ戻す
USER appuser
