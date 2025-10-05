from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from datetime import datetime, timedelta
from settee_app.models import Message

class Command(BaseCommand):
    help = (
        "Message テーブルを削除します。\n"
        "既定は DRY-RUN（件数だけ表示）。--yes を付けると実際に削除します。\n"
        "オプション: --older-than を指定すると、指定日時より古いレコードのみ削除します。"
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--yes",
            action="store_true",
            help="本当に削除します（確認なし）。付けない場合は DRY-RUN。",
        )
        parser.add_argument(
            "--older-than",
            type=str,
            default=None,
            help=(
                "この日時より古いメッセージだけ削除（ISO8601 例: 2025-01-01T00:00:00）。"
                " '30d' のように日数指定も可（例: 30d=30日前より古い）。"
            ),
        )
        parser.add_argument(
            "--chunk-size",
            type=int,
            default=5000,
            help="大量データ向けに分割削除する件数（既定 5000）。",
        )

    def _parse_older_than(self, s: str):
        # '30d' 形式（相対日数） or ISO8601 を受け付け
        if not s:
            return None
        s = s.strip()
        if s.endswith("d") and s[:-1].isdigit():
            days = int(s[:-1])
            return timezone.now() - timedelta(days=days)
        # ISO8601（タイムゾーン無しも受け付け、なければ naive→UTC想定）
        try:
            dt = datetime.fromisoformat(s)
            if timezone.is_naive(dt):
                dt = timezone.make_aware(dt, timezone=timezone.utc)
            return dt
        except Exception:
            raise SystemExit(f"--older-than の書式が不正です: {s}")

    def handle(self, *args, **options):
        older_than = self._parse_older_than(options.get("older_than"))
        chunk_size = options["chunk_size"]
        do_delete  = options["yes"]

        qs = Message.objects.all()
        if older_than:
            qs = qs.filter(timestamp__lt=older_than)

        total = qs.count()
        if total == 0:
            self.stdout.write(self.style.WARNING("対象メッセージはありません。"))
            return

        self.stdout.write(
            self.style.NOTICE(
                f"対象メッセージ件数: {total}"
                + (f"（{older_than.isoformat()} より古い）" if older_than else "（全件）")
            )
        )

        if not do_delete:
            self.stdout.write(self.style.SUCCESS("DRY-RUN のため削除しません。--yes を付けると実行します。"))
            return

        self.stdout.write(self.style.WARNING("削除を開始します…"))

        # 大量削除でも DB を詰まらせないようにチャンク実行
        deleted = 0
        # id 昇順で PK を取り出して分割削除
        pks = list(qs.order_by("id").values_list("id", flat=True))
        while pks:
            batch = pks[:chunk_size]
            del pks[:chunk_size]
            # 1バッチずつコミット（長時間ロックの回避）
            with transaction.atomic():
                Message.objects.filter(id__in=batch).delete()
            deleted += len(batch)
            self.stdout.write(f"  … {deleted}/{total} 件削除")

        self.stdout.write(self.style.SUCCESS(f"削除完了: {deleted} 件"))
