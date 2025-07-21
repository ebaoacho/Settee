# scripts/remove_station_suffix.py

from django.core.management.base import BaseCommand
from settee_app.models import UserProfile

class Command(BaseCommand):
    help = "selected_area の '駅' を削除して '新宿' のように修正します"

    def handle(self, *args, **options):
        updated_count = 0

        users = UserProfile.objects.all()
        for user in users:
            original = user.selected_area
            modified = [area.replace('駅', '') for area in original]

            if modified != original:
                user.selected_area = modified
                user.save()
                updated_count += 1
                self.stdout.write(f"[更新] {user.nickname}: {original} → {modified}")

        if updated_count == 0:
            self.stdout.write(self.style.WARNING("更新対象のユーザーはありませんでした。"))
        else:
            self.stdout.write(self.style.SUCCESS(f"{updated_count} 件のユーザーを更新しました。"))
