-- CDCの動作確認に使用する注文テーブルを、存在しない場合だけ作成
CREATE TABLE IF NOT EXISTS public.orders (
  -- 注文を一意に識別する自動採番の主キー
  id BIGSERIAL PRIMARY KEY,
  -- 注文したユーザーの識別子
  user_id BIGINT NOT NULL,
  -- 注文金額（このサンプルでは整数で保持）
  amount BIGINT NOT NULL,
  -- created、paidなどの注文状態
  status VARCHAR(30) NOT NULL,
  -- レコード作成日時。未指定時はPostgreSQLサーバーの現在時刻を使用
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- UPDATE・DELETE時に変更前の全列をWALへ記録し、Debeziumが完全な変更前データを取得できるようにする
ALTER TABLE public.orders REPLICA IDENTITY FULL;
