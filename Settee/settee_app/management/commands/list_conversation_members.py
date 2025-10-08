from __future__ import annotations

import json
from typing import Iterable, Optional

from django.core.management.base import BaseCommand
from django.db.models import Prefetch, Q
from django.utils.timezone import localtime

from settee_app.models import (
    Conversation,
    ConversationMember,
    UserProfile,
)


def _iso(dt):
    if not dt:
        return None
    return localtime(dt).isoformat(timespec="seconds")


def _model_has_field(model, field_name: str) -> bool:
    return any(getattr(f, "name", None) == field_name for f in model._meta.get_fields())


class Command(BaseCommand):
    help = "会話とメンバー一覧を出力します。--json でJSON、未指定で表形式。最新の invited_by / invited_at に対応。"

    def add_arguments(self, parser):
        parser.add_argument(
            "--conversation",
            type=int,
            nargs="*",
            help="会話ID（複数可）を指定すると、その会話だけを出力",
        )
        parser.add_argument(
            "--user-id",
            type=str,
            help="このユーザーが所属する会話だけを出力（UserProfile.user_id）",
        )
        parser.add_argument(
            "--kind",
            type=str,
            choices=["dm", "double", "group"],
            help="会話の種別で絞り込み（dm/double/group）",
        )
        parser.add_argument(
            "--include-left",
            action="store_true",
            help="退室済み(left_atあり)のメンバーも含めて出力（デフォルトは在室のみ）",
        )
        parser.add_argument(
            "--json",
            action="store_true",
            help="JSON形式で出力（未指定なら表形式）",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=None,
            help="出力会話数の上限（新しい順）",
        )

    def handle(self, *args, **options):
        conv_ids: Optional[Iterable[int]] = options.get("conversation")
        user_id: Optional[str] = options.get("user_id")
        kind: Optional[str] = options.get("kind")
        include_left: bool = options.get("include_left")
        as_json: bool = options.get("json")
        limit: Optional[int] = options.get("limit")

        # ベースQuery（新しい更新順）
        qs = (
            Conversation.objects
            .select_related("matched_pair_a", "matched_pair_b")
            .all()
            .order_by("-last_message_at", "-updated_at", "-id")
        )

        if conv_ids:
            qs = qs.filter(id__in=conv_ids)

        if kind:
            qs = qs.filter(kind=kind)

        if user_id:
            # デフォルトは在室メンバーとして紐づく会話に限定
            base = Q(members__user__user_id=user_id)
            if not include_left:
                base &= Q(members__left_at__isnull=True)
            qs = qs.filter(base)

        # ConversationMember に invited_by / invited_at があるかを安全に確認
        has_invited_by = _model_has_field(ConversationMember, "invited_by")
        has_invited_at = _model_has_field(ConversationMember, "invited_at")

        # メンバーを事前フェッチ
        member_filter = Q()
        if not include_left:
            member_filter &= Q(left_at__isnull=True)

        member_qs = (
            ConversationMember.objects.filter(member_filter)
            .select_related("user")
            .order_by("joined_at", "id")
        )
        if has_invited_by:
            member_qs = member_qs.select_related("invited_by")

        qs = qs.prefetch_related(Prefetch("members", queryset=member_qs))

        if limit:
            qs = qs[:limit]

        conversations = list(qs)

        if as_json:
            self._print_json(conversations, has_invited_by=has_invited_by, has_invited_at=has_invited_at)
        else:
            self._print_table(conversations, include_left=include_left, has_invited_by=has_invited_by, has_invited_at=has_invited_at)

    # ------------ 出力: JSON ------------
    def _print_json(self, conversations: list[Conversation], *, has_invited_by: bool, has_invited_at: bool) -> None:
        payload = []
        for conv in conversations:
            item = {
                "id": conv.id,
                "kind": conv.kind,
                "title": conv.title or "",
                "created_at": _iso(conv.created_at),
                "updated_at": _iso(conv.updated_at),
                "last_message_at": _iso(conv.last_message_at),
                "matched_pair": [
                    getattr(conv.matched_pair_a, "user_id", None),
                    getattr(conv.matched_pair_b, "user_id", None),
                ],
                "members": [],
            }
            for mem in conv.members.all():
                u: UserProfile = mem.user
                invited_by_uid = getattr(getattr(mem, "invited_by", None), "user_id", None) if has_invited_by else None
                invited_at_iso = _iso(getattr(mem, "invited_at", None)) if has_invited_at else None
                item["members"].append(
                    {
                        "user_id": u.user_id if u else None,
                        "nickname": u.nickname if u else None,
                        "role": mem.role,
                        "is_muted": mem.is_muted,
                        "joined_at": _iso(mem.joined_at),
                        "left_at": _iso(mem.left_at),
                        "invited_by": invited_by_uid,
                        "invited_at": invited_at_iso,
                    }
                )
            payload.append(item)

        self.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2))

    # ------------ 出力: 表形式 ------------
    def _print_table(
        self,
        conversations: list[Conversation],
        *,
        include_left: bool,
        has_invited_by: bool,
        has_invited_at: bool,
    ) -> None:
        if not conversations:
            self.stdout.write(self.style.WARNING("会話が見つかりませんでした。"))
            return

        for conv in conversations:
            header = f"[{conv.id}] kind={conv.kind} title='{conv.title or ''}'"
            sub = f" created={_iso(conv.created_at)} last_message={_iso(conv.last_message_at)}"
            mpair = (
                f" matched_pair=({getattr(conv.matched_pair_a, 'user_id', None)},"
                f"{getattr(conv.matched_pair_b, 'user_id', None)})"
            )
            self.stdout.write(self.style.MIGRATE_HEADING(header))
            self.stdout.write(self.style.HTTP_INFO(sub + " " + mpair))

            members = list(conv.members.all())
            if not members:
                self.stdout.write("  (メンバーなし)\n")
                continue

            # 表ヘッダ
            if has_invited_by or has_invited_at:
                self.stdout.write(
                    "  {0:<18}  {1:<16}  {2:<8}  {3:<6}  {4:<19}  {5:<18}  {6:<19}  {7:<19}".format(
                        "user_id", "nickname", "role", "muted", "joined_at", "invited_by", "invited_at", "left_at"
                    )
                )
                self.stdout.write("  " + "-" * 140)
            else:
                self.stdout.write(
                    "  {0:<18}  {1:<16}  {2:<8}  {3:<6}  {4:<19}  {5:<19}".format(
                        "user_id", "nickname", "role", "muted", "joined_at", "left_at"
                    )
                )
                self.stdout.write("  " + "-" * 94)

            for m in members:
                u: UserProfile = m.user
                if has_invited_by or has_invited_at:
                    invited_by_uid = getattr(getattr(m, "invited_by", None), "user_id", None)
                    invited_at_iso = _iso(getattr(m, "invited_at", None))
                    self.stdout.write(
                        "  {user_id:<18}  {nick:<16}  {role:<8}  {muted:<6}  {joined:<19}  {invby:<18}  {invat:<19}  {left:<19}".format(
                            user_id=(u.user_id if u else "DELETED")[:18],
                            nick=(u.nickname if u else "-")[:16],
                            role=(m.role or "member")[:8],
                            muted=str(bool(m.is_muted))[:6],
                            joined=_iso(m.joined_at) or "-",
                            invby=(invited_by_uid or "-")[:18],
                            invat=invited_at_iso or "-",
                            left=_iso(m.left_at) or "-",
                        )
                    )
                else:
                    self.stdout.write(
                        "  {user_id:<18}  {nick:<16}  {role:<8}  {muted:<6}  {joined:<19}  {left:<19}".format(
                            user_id=(u.user_id if u else "DELETED")[:18],
                            nick=(u.nickname if u else "-")[:16],
                            role=(m.role or "member")[:8],
                            muted=str(bool(m.is_muted))[:6],
                            joined=_iso(m.joined_at) or "-",
                            left=_iso(m.left_at) or "-",
                        )
                    )

            # 在室/退室サマリ
            active = sum(1 for m in members if m.left_at is None)
            self.stdout.write(
                f"\n  members: total={len(members)} active={active} {'(含む退室者)' if include_left else ''}\n"
            )
