# scripts/print_matches.py
from django.core.management.base import BaseCommand
from settee_app.models import Match
from django.utils import timezone

class Command(BaseCommand):
    help = '全Matchレコードを表示します'

    def handle(self, *args, **options):
        matches = Match.objects.all().select_related('user_lower_id', 'user_higher_id')

        if not matches.exists():
            self.stdout.write(self.style.WARNING("マッチが存在しません。"))
            return

        def fmt(v):
            """None/空を '未設定'、日時を見やすく整形"""
            if v is None:
                return "未設定"
            if isinstance(v, str):
                return v if v.strip() else "未設定"
            if hasattr(v, "isoformat"):
                return v.isoformat()
            return str(v)

        def seen_status(seen, seen_at):
            """既読状態を絵文字付きで表示"""
            if seen:
                return f"✓ 既読 ({fmt(seen_at)})"
            return "✗ 未読"

        for m in matches:
            w = self.stdout.write
            w(self.style.SUCCESS("─" * 60))
            w(f"マッチID　　　　　: {m.id}")
            w(f"ユーザー1 (lower)　: {m.user_lower_id.user_id} ({m.user_lower_id.nickname})")
            w(f"ユーザー2 (higher) : {m.user_higher_id.user_id} ({m.user_higher_id.nickname})")
            w(f"マッチ成立日時　　: {fmt(m.matched_at)}")
            w("")
            w(self.style.HTTP_INFO("【既読状態】"))
            w(f"  {m.user_lower_id.user_id} : {seen_status(m.lower_user_seen, m.lower_user_seen_at)}")
            w(f"  {m.user_higher_id.user_id} : {seen_status(m.higher_user_seen, m.higher_user_seen_at)}")
            
        w(self.style.SUCCESS("─" * 60))
        w(self.style.SUCCESS(f"合計: {matches.count()}件のマッチ"))