# ベースイメージとして公式のPythonイメージを使用
FROM python:3.13.3

# 必要なシステムパッケージをインストール
RUN apt-get update && \
    apt-get install -y build-essential libpq-dev && \
    apt-get clean

# 作業ディレクトリを設定
WORKDIR /settee_server

# 必要なライブラリをインストール
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# プロジェクトのファイルをコピー
COPY . .

# ポートを開放
EXPOSE 8000

# コマンドを実行して、開発サーバを起動
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
