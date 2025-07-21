# scripts/print_like_actions.py

from django.core.management.base import BaseCommand
from settee_app.models import LikeAction
import json

class Command(BaseCommand):
    help = '全LikeActionレコードを表示します'

    def handle(self, *args, **options):
        likes = LikeAction.objects.select_related('sender', 'receiver').all().order_by('-created_at')

        if not likes.exists():
            self.stdout.write(self.style.WARNING("Likeアクションが存在しません。"))
            return

        for like in likes:
            self.stdout.write(self.style.SUCCESS("─" * 40))
            self.stdout.write(f"送信者: {like.sender.nickname}（{like.sender.user_id}）")
            self.stdout.write(f"受信者: {like.receiver.nickname}（{like.receiver.user_id}）")
            self.stdout.write(f"種類　: {self._get_like_type_label(like.like_type)}")
            self.stdout.write(f"日時　: {like.created_at.strftime('%Y-%m-%d %H:%M:%S')}")

    def _get_like_type_label(self, like_type):
        mapping = {
            0: 'Like',
            1: 'Super Like',
            2: 'ごちそうLike',
            3: 'メッセージLike',
        }
        return mapping.get(like_type, f"不明（{like_type}）")
