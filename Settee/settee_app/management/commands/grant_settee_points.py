# settee_app/management/commands/grant_settee_points.py
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from settee_app.models import UserProfile


class Command(BaseCommand):
    help = "Grant or deduct Settee points to a specific user."

    def add_arguments(self, parser):
        # 付与/減算ポイント（負数で減算）
        parser.add_argument(
            "amount",
            type=int,
            help="Number of points to add (use negative to deduct).",
        )

        # ユーザーの特定方法（どれか1つ必須）
        identify = parser.add_mutually_exclusive_group(required=True)
        identify.add_argument("--user-id", dest="user_id", help="UserProfile.user_id")
        identify.add_argument("--email", dest="email", help="UserProfile.email")
        identify.add_argument("--phone", dest="phone", help="UserProfile.phone")

        parser.add_argument(
            "--reason",
            default="",
            help="Reason for audit trail (printed to stdout).",
        )
        parser.add_argument(
            "--yes",
            action="store_true",
            help="Do not ask for confirmation (non-interactive).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Print what would happen but do not write to DB.",
        )
        parser.add_argument(
            "--allow-negative",
            action="store_true",
            help="Allow balance to go below zero (otherwise command errors).",
        )

    def handle(self, *args, **options):
        amount = options["amount"]
        if amount == 0:
            raise CommandError("amount must be non-zero.")

        # 対象ユーザー取得
        try:
            if options.get("user_id"):
                user = UserProfile.objects.get(user_id=options["user_id"])
            elif options.get("email"):
                user = UserProfile.objects.get(email=options["email"])
            else:
                user = UserProfile.objects.get(phone=options["phone"])
        except UserProfile.DoesNotExist:
            raise CommandError("User not found.")

        before = int(getattr(user, "settee_points", 0) or 0)
        after = before + amount

        # マイナス残高許可チェック
        if after < 0 and not options["allow_negative"]:
            raise CommandError(
                f"Operation would make balance negative ({after}). "
                f"Use --allow-negative to force."
            )

        now = timezone.now().isoformat()
        self.stdout.write("--- Settee Points Adjustment ---")
        self.stdout.write(f"User         : {user.nickname} ({user.user_id}, {user.email})")
        self.stdout.write(f"Current      : {before}")
        self.stdout.write(f"Change       : {amount} ({'add' if amount > 0 else 'deduct'})")
        self.stdout.write(f"New balance  : {after}")
        if options["reason"]:
            self.stdout.write(f"Reason       : {options['reason']}")
        self.stdout.write(f"Server time  : {now}")
        self.stdout.write(f"Dry-run      : {options['dry_run']}")

        if options["dry_run"]:
            self.stdout.write(self.style.WARNING("Dry-run only. No changes written."))
            return

        if not options["yes"]:
            confirm = input("Proceed? [y/N]: ").strip().lower()
            if confirm not in ("y", "yes"):
                self.stdout.write(self.style.WARNING("Aborted by user."))
                return

        # 競合に強い更新（原子的に反映）
        with transaction.atomic():
            u = UserProfile.objects.select_for_update().get(pk=user.pk)
            before2 = int(getattr(u, "settee_points", 0) or 0)
            after2 = before2 + amount
            if after2 < 0 and not options["allow_negative"]:
                raise CommandError(
                    f"Concurrent update would make balance negative ({after2}). "
                    f"Use --allow-negative to force."
                )
            u.settee_points = after2
            u.save(update_fields=["settee_points"])

        self.stdout.write(self.style.SUCCESS(f"Done. New balance = {after2}"))
