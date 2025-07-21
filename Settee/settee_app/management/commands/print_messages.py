from django.core.management.base import BaseCommand
from settee_app.models import Message

class Command(BaseCommand):
    help = 'Messagesテーブルの内容を表示します'

    def handle(self, *args, **kwargs):
        messages = Message.objects.all().order_by('timestamp')

        if not messages.exists():
            self.stdout.write(self.style.WARNING("📭 メッセージが1件も存在しません"))
            return

        for msg in messages:
            self.stdout.write(
                f"[{msg.timestamp}] {msg.sender.user_id} → {msg.receiver.user_id}: {msg.text}"
            )
