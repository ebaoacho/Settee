import os
import shutil
import random
from django.core.management.base import BaseCommand
from django.conf import settings
from settee_app.models import UserProfile
from django.contrib.auth.hashers import make_password
from datetime import date, timedelta

class Command(BaseCommand):
    help = "男性の大学生用 UserProfile を user_51〜user_100 まで新規作成し、画像を保存"

    def handle(self, *args, **options):
        BASE_IMAGE_DIR = "./material/Male"  # ★←ここをローカル画像パスに変更
        SAVE_DIR = settings.MEDIA_ROOT
        os.makedirs(SAVE_DIR, exist_ok=True)

        # 男性ニックネーム（日本人大学生風）
        nicknames = [
            "たくみ", "けんた", "ゆうた", "しょう", "たいち", "りょう", "はやと", "だいき", "けいた", "しゅん",
            "ゆうま", "かずき", "なおや", "そうた", "ゆうき", "ゆうと", "れん", "ひろと", "たくや", "しん",
            "けいすけ", "ひろき", "はるき", "けん", "ゆうだい", "ともや", "こうた", "りく", "あきら", "りゅうた",
            "かいと", "ゆうへい", "たいが", "なおと", "けい", "ゆうしん", "そうま", "しゅうへい", "まさき", "けんしん",
            "ひかる", "しんじ", "たかし", "まこと", "りょうた", "ゆう", "つばさ", "かずま", "せいや", "こうへい"
        ]

        STATIONS = ["池袋", "新宿", "渋谷", "横浜"]
        UNIVERSITIES = ["東京大学", "慶應義塾大学", "早稲田大学", "明治大学"]
        BLOOD_TYPES = ["A型", "B型", "O型", "AB型"]
        HEIGHTS = ["165cm", "170cm", "175cm", "180cm", "185cm"]
        DRINKINGS = ["飲まない", "たまに飲む", "よく飲む"]
        SMOKINGS = ["吸わない", "たまに吸う", "吸う"]

        for i in range(50):
            user_id = f"user_{51 + i}"
            nickname = nicknames[i]
            person_folder = os.path.join(BASE_IMAGE_DIR, f"person_{1 + i}")
            if not os.path.exists(person_folder):
                self.stdout.write(self.style.WARNING(f"⚠ person_{1 + i} フォルダが見つかりません"))
                continue

            profile = UserProfile.objects.create(
                phone=f"0805678{i:04d}",
                email=f"{user_id}@example.com",
                gender="男性",
                birth_date=date.today() - timedelta(days=random.randint(7000, 11000)),
                nickname=nickname,
                user_id=user_id,
                password=make_password("password123"),
                selected_area=random.sample(STATIONS, k=random.randint(1, 3)),
                match_multiple=random.choice([True, False]),
                occupation="学生",
                university=random.choice(UNIVERSITIES),
                blood_type=random.choice(BLOOD_TYPES),
                height=random.choice(HEIGHTS),
                drinking=random.choice(DRINKINGS),
                smoking=random.choice(SMOKINGS),
            )

            # 画像保存先
            dest_user_dir = os.path.join(SAVE_DIR, user_id)
            os.makedirs(dest_user_dir, exist_ok=True)

            image_files = sorted([f for f in os.listdir(person_folder) if f.endswith(".png")])
            for idx, fname in enumerate(image_files, 1):
                src_path = os.path.join(person_folder, fname)
                dst_path = os.path.join(dest_user_dir, f"{user_id}_{idx}.png")
                shutil.copy(src_path, dst_path)

            self.stdout.write(self.style.SUCCESS(f"✅ {user_id}（{nickname}）を作成し、画像を保存しました"))
