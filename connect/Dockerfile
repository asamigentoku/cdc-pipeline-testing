FROM confluentinc/cp-kafka-connect:7.9.0
USER root
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest \
 && confluent-hub install --no-prompt wepay/kafka-connect-bigquery:latest
USER appuser
