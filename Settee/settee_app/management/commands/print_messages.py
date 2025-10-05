# settee_app/management/commands/print_messages.py
from django.core.management.base import BaseCommand
from settee_app.models import Message

class Command(BaseCommand):
    help = "Print messages safely (handles deleted users)"

    def handle(self, *args, **options):
        qs = Message.objects.select_related('sender', 'receiver').order_by('timestamp')
        for msg in qs:
            s = getattr(msg.sender, 'user_id', '退会したユーザー')
            r = getattr(msg.receiver, 'user_id', '退会したユーザー')
            self.stdout.write(f"[{msg.timestamp}] {s} → {r}: {msg.text}")
