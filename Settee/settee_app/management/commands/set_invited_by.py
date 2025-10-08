# yourapp/management/commands/set_invited_by.py
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from settee_app.models import ConversationMember, UserProfile, Conversation

class Command(BaseCommand):
    help = (
        "Set/clear ConversationMember.invited_by.\n"
        "指定方法は (1) --member-id で直接、または "
        "(2) --conversation + --user（user_id か PK）で会話とユーザーを指定。"
    )

    def add_arguments(self, parser):
        target = parser.add_argument_group("Target selection (どちらか一方は必須)")
        target.add_argument("--member-id", type=int, help="ConversationMember の PK")
        target.add_argument("--conversation", "-c", type=int, help="Conversation の ID")
        target.add_argument("--user", "-u", type=str, help="対象メンバーの user_id か UserProfile の PK")

        action = parser.add_argument_group("Action")
        action.add_argument("--inviter", "-i", type=str,
                            help="invited_by に設定する招待者。user_id か UserProfile の PK")
        action.add_argument("--clear", action="store_true",
                            help="invited_by を NULL にする")
        action.add_argument("--dry-run", action="store_true",
                            help="実際には更新せず内容のみ表示")
        action.add_argument("--yes", "-y", action="store_true",
                            help="確認プロンプトなしで実行")

    def _resolve_user(self, token: str) -> UserProfile:
        """
        token が数値なら PK とみなし、それ以外は user_id として解決
        """
        if token.isdigit():
            return UserProfile.objects.get(pk=int(token))
        return UserProfile.objects.get(user_id=token)

    def _get_member(self, options) -> ConversationMember:
        member_id = options.get("member_id")
        conv_id   = options.get("conversation")
        user_tok  = options.get("user")

        if member_id:
            try:
                return (ConversationMember.objects
                        .select_related("user", "conversation", "invited_by")
                        .get(pk=member_id))
            except ConversationMember.DoesNotExist:
                raise CommandError(f"ConversationMember(pk={member_id}) が見つかりません")

        if conv_id and user_tok:
            try:
                user = self._resolve_user(user_tok)
            except UserProfile.DoesNotExist:
                raise CommandError(f"UserProfile({user_tok}) が見つかりません")

            try:
                return (ConversationMember.objects
                        .select_related("user", "conversation", "invited_by")
                        .get(conversation_id=conv_id, user=user))
            except ConversationMember.DoesNotExist:
                raise CommandError(f"ConversationMember(conversation_id={conv_id}, user={user.user_id}) が見つかりません")

        raise CommandError("ターゲット未指定: --member-id か、--conversation と --user を指定してください。")

    def handle(self, *args, **options):
        clear   = options["clear"]
        inviter_tok = options.get("inviter")
        dry_run = options["dry_run"]
        yes     = options["yes"]

        if not clear and not inviter_tok:
            # 参照モード：現在値を表示して終了
            cm = self._get_member(options)
            current = cm.invited_by.user_id if cm.invited_by_id else None
            self.stdout.write(
                f"[SHOW] cm_id={cm.id} conv={cm.conversation_id} user={cm.user.user_id} "
                f"invited_by={current}"
            )
            return

        new_inviter = None
        if not clear:
            try:
                new_inviter = self._resolve_user(inviter_tok)
            except UserProfile.DoesNotExist:
                raise CommandError(f"招待者 UserProfile({inviter_tok}) が見つかりません")

        cm = self._get_member(options)
        before = cm.invited_by.user_id if cm.invited_by_id else None
        after  = (new_inviter.user_id if new_inviter else None)

        self.stdout.write(
            f"[PLAN] cm_id={cm.id} conv={cm.conversation_id} member={cm.user.user_id} "
            f"invited_by: {before} -> {after}"
        )

        if dry_run:
            self.stdout.write(self.style.WARNING("dry-run: 変更はコミットされません"))
            return

        if not yes:
            confirm = input("実行してよろしいですか？ [y/N]: ").strip().lower()
            if confirm not in ("y", "yes"):
                self.stdout.write(self.style.WARNING("キャンセルしました"))
                return

        with transaction.atomic():
            # 競合を避けて確実に反映
            cm_for_update = (ConversationMember.objects
                             .select_for_update()
                             .get(pk=cm.pk))
            cm_for_update.invited_by = new_inviter  # None 可
            cm_for_update.save(update_fields=["invited_by"])

        self.stdout.write(self.style.SUCCESS(
            f"更新完了: cm_id={cm.id} invited_by={after}"
        ))
