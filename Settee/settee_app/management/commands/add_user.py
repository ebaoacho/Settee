import os
import shutil
import random
from django.core.management.base import BaseCommand
from django.conf import settings
from settee_app.models import UserProfile
from django.contrib.auth.hashers import make_password
from datetime import date, timedelta

class Command(BaseCommand):
    help = "ランダムな画像からデモ用アカウントを作成します"

    def handle(self, *args, **options):
        FEMALE_IMAGE_DIR = "/app/materials/Female"
        MALE_IMAGE_DIR = "/app/materials/Male"
        SAVE_DIR = os.path.join(settings.MEDIA_ROOT)
        os.makedirs(SAVE_DIR, exist_ok=True)

        female_nicknames = [
            "あやか", "さき", "まい", "みずき", "ゆき", "あかね", "はるか", "みほ", "かな", "なお",
            "えり", "あすか", "りさ", "ちひろ", "あみ", "もも", "かすみ", "ひかり", "ゆい", "ちか"
        ]
        male_nicknames = [
            "たけし", "ゆうた", "しょうた", "けんた", "だいち", "かずき", "ゆうき", "なおき", "たくや", "りょう"
        ]

        STATIONS = ["池袋", "新宿", "渋谷", "横浜"]
        UNIVERSITIES = ["東京大学", "慶應義塾大学", "早稲田大学", "明治大学"]
        BLOOD_TYPES = ["A型", "B型", "O型", "AB型"]
        HEIGHTS = ["165cm", "170cm", "175cm", "180cm", "185cm"]
        DRINKINGS = ["飲まない", "たまに飲む", "よく飲む"]
        SMOKINGS = ["吸わない", "たまに吸う", "吸う"]

        for i in range(20):  # 作成するユーザー数
            gender = random.choice(["女性", "男性"])
            user_id = f"demo_user_{i+1}"
            nickname = random.choice(female_nicknames if gender == "女性" else male_nicknames)
            image_dir = FEMALE_IMAGE_DIR if gender == "女性" else MALE_IMAGE_DIR

            IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".JPG", ".JPEG", ".HEIC")

            all_images = [f for f in os.listdir(image_dir) if f.endswith(IMAGE_EXTENSIONS)]
            if all_images:
                k = min(len(all_images), random.randint(1, 3))
                selected_images = random.sample(all_images, k=k)
            else:
                self.stdout.write(self.style.WARNING("No images found. Skipping user creation."))
                return

            profile = UserProfile.objects.create(
                phone=f"0905555{i:04d}",
                email=f"{user_id}@example.com",
                gender=gender,
                birth_date=date.today() - timedelta(days=random.randint(7000, 11000)),
                nickname=nickname,
                user_id=user_id,
                password=make_password("password123"),
                selected_area=STATIONS,  # 全部選択
                match_multiple=random.choice([True, False]),
                occupation="学生",
                university=random.choice(UNIVERSITIES),
                blood_type=random.choice(BLOOD_TYPES),
                height=random.choice(HEIGHTS),
                drinking=random.choice(DRINKINGS),
                smoking=random.choice(SMOKINGS),
            )

            dest_user_dir = os.path.join(SAVE_DIR, user_id)
            os.makedirs(dest_user_dir, exist_ok=True)

            for idx, fname in enumerate(selected_images, 1):
                src_path = os.path.join(image_dir, fname)
                dst_path = os.path.join(dest_user_dir, f"{user_id}_{idx}.png")
                shutil.copy(src_path, dst_path)

            self.stdout.write(self.style.SUCCESS(f"✅ {user_id}（{nickname}）を作成し、画像{len(selected_images)}枚を保存しました"))
