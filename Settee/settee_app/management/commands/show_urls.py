# settee_app/management/commands/show_urls.py

from django.core.management.base import BaseCommand
from django.urls import get_resolver

class Command(BaseCommand):
    help = '全てのURLパターンを表示し、バインド先のファイル絶対パスも出力します'

    def handle(self, *args, **kwargs):
        self.stdout.write("=== URL パターン一覧 (ビュー関数とファイルパス) ===")
        for pattern in get_resolver().url_patterns:
            view = pattern.callback
            try:
                source_path = view.__code__.co_filename
                self.stdout.write(f"{pattern.pattern} -> {view.__module__}.{view.__name__}")
                self.stdout.write(f"    ↳ ファイル: {source_path}")
            except Exception as e:
                self.stdout.write(f"{pattern.pattern} -> [関数の情報取得に失敗] ({e})")
