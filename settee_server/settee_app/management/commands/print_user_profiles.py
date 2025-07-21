# scripts/print_user_profiles.py

from django.core.management.base import BaseCommand
from settee_app.models import UserProfile
import json

class Command(BaseCommand):
    help = '全UserProfileレコードを表示します'

    def handle(self, *args, **options):
        users = UserProfile.objects.all()

        if not users.exists():
            self.stdout.write(self.style.WARNING("ユーザーが存在しません。"))
            return

        for user in users:
            self.stdout.write(self.style.SUCCESS("─" * 40))
            self.stdout.write(f"ニックネーム　　　: {user.nickname}")
            self.stdout.write(f"メールアドレス　　: {user.email}")
            self.stdout.write(f"電話番号　　　　　: {user.phone}")
            self.stdout.write(f"性別　　　　　　　: {user.gender}")
            self.stdout.write(f"生年月日　　　　　: {user.birth_date}")
            self.stdout.write(f"ユーザーID　　　　: {user.user_id}")
            self.stdout.write(f"ハッシュパスワード: {user.password}")
            self.stdout.write(f"よく遊ぶエリア　　: {json.dumps(user.selected_area, ensure_ascii=False)}")
            self.stdout.write(f"マッチ人数　　　　: {'みんなで' if user.match_multiple else 'ひとりで'}")
            self.stdout.write(f"会える日付リスト　: {[d.isoformat() for d in user.available_dates]}")
