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

        def fmt(v):
            """None/空文字/空配列を '未設定'、配列や日付を見やすく整形"""
            if v is None:
                return "未設定"
            if isinstance(v, str):
                return v if v.strip() else "未設定"
            if isinstance(v, list):
                if len(v) == 0:
                    return "未設定"
                # DateField(ArrayField) 用
                if all(hasattr(d, "isoformat") for d in v):
                    return "[" + ", ".join(d.isoformat() for d in v) + "]"
                return json.dumps(v, ensure_ascii=False)
            # DateField 単体など
            if hasattr(v, "isoformat"):
                return v.isoformat()
            return str(v)

        for u in users:
            w = self.stdout.write
            w(self.style.SUCCESS("─" * 50))
            w(f"ユーザID　　　　　: {fmt(u.user_id)}")
            w(f"ニックネーム　　　: {fmt(u.nickname)}")
            w(f"メールアドレス　　: {fmt(u.email)}")
            w(f"電話番号　　　　　: {fmt(u.phone)}")
            w(f"性別　　　　　　　: {fmt(u.gender)}")
            w(f"生年月日　　　　　: {fmt(u.birth_date)}")
            w(f"ユーザーID　　　　: {fmt(u.user_id)}")
            w(f"ハッシュパスワード: {u.password}")
            w(f"よく遊ぶエリア　　: {fmt(u.selected_area)}")
            w(f"マッチ人数　　　　: {'みんなで' if u.match_multiple else 'ひとりで'}")
            w(f"会える日付リスト　: {fmt(u.available_dates)}")
            # ここから任意項目
            w(f"職業　　　　　　　: {fmt(u.occupation)}")
            w(f"学校名　　　　　　: {fmt(u.university)}")
            w(f"血液型　　　　　　: {fmt(u.blood_type)}")
            w(f"身長　　　　　　　: {fmt(u.height)}")
            w(f"お酒　　　　　　　: {fmt(u.drinking)}")
            w(f"煙草　　　　　　　: {fmt(u.smoking)}")
            w(f"星座　　　　　　　: {fmt(u.zodiac)}")
            w(f"MBTI　　　　　　 : {fmt(u.mbti)}")
            w(f"求めているのは　　: {fmt(u.seeking)}")
            w(f"好み　　　　　　　: {fmt(u.preference)}")
