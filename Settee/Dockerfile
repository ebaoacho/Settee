# Pythonベースの軽量イメージを使用
FROM python:3.13.3-slim

# 必要なパッケージをインストール
RUN apt-get update && \
    apt-get install -y build-essential libpq-dev netcat-openbsd && \
    apt-get clean

# 作業ディレクトリを設定
WORKDIR /app

# requirements.txt をコピーしてライブラリをインストール
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# アプリコードと wait-for-it.sh をコピー
COPY . .
COPY wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh

# ポートを開放（ALB で使用）
EXPOSE 8000

# Gunicorn を使用して Django WSGI を起動
CMD ["/wait-for-it.sh", "db:5432", "--", "gunicorn", "settee_config.wsgi:application", "--bind", "0.0.0.0:8000"]
