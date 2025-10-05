# settee_app/management/commands/backfill_image_assets.py
import os
import re
from pathlib import Path
from typing import Optional

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from settee_app.models import UserProfile, ImageAsset  # あなたの UserProfile の実パスに合わせて

# 許可する拡張子（小文字）
ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}  # 必要に応じて調整

# ファイル名の想定パターン: <user_id>_<index>.<ext>
FILENAME_RE = re.compile(r"^(?P<uid>.+)_(?P<idx>\d+)(?P<ext>\.[A-Za-z0-9]+)$")

def infer_image_index(user_id: str, filename: str) -> Optional[int]:
    """
    可能ならファイル名から image_index を復元する。
    例: user123_2.jpg -> 2
    user_id が一致しない/パース不可なら None を返す。
    """
    m = FILENAME_RE.match(filename)
    if not m:
        return None
    uid = m.group("uid")
    if uid != user_id:
        return None
    try:
        return int(m.group("idx"))
    except Exception:
        return None


class Command(BaseCommand):
    help = (
        "Scan /images/<user_id>/* and upsert ImageAsset rows.\n"
        "By default, scans settings.BASE_DIR / 'images'."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--root",
            type=str,
            default=None,
            help="Root directory to scan. Default: settings.BASE_DIR / 'images'",
        )
        parser.add_argument(
            "--user-id",
            type=str,
            default=None,
            help="If provided, only backfill for this user_id.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Do not write to DB; only print what would change.",
        )
        parser.add_argument(
            "--reset-reviewed",
            action="store_true",
            help="When updating an existing row, reset reviewed=False & moderation_status='pending'.",
        )

    def handle(self, *args, **options):
        root = options["root"]
        if not root:
            root = os.path.join(settings.BASE_DIR, "images")
        root_path = Path(root)

        if not root_path.exists() or not root_path.is_dir():
            raise CommandError(f"Images root not found: {root_path}")

        target_user_id = options["user_id"]
        dry_run = options["dry_run"]
        reset_reviewed = options["reset_reviewed"]

        if target_user_id:
            user_dirs = [root_path / target_user_id]
        else:
            # 直下のディレクトリ（= user_id）を列挙
            user_dirs = [p for p in root_path.iterdir() if p.is_dir()]

        total_new = 0
        total_updated = 0
        total_skipped = 0

        self.stdout.write(self.style.NOTICE(f"Scanning: {root_path}"))
        if target_user_id:
            self.stdout.write(self.style.NOTICE(f"Filter user_id: {target_user_id}"))
        if dry_run:
            self.stdout.write(self.style.WARNING("DRY RUN mode (no DB writes)."))

        for user_dir in sorted(user_dirs):
            user_id = user_dir.name

            # ユーザーが存在しない場合はスキップ
            try:
                user = UserProfile.objects.get(user_id=user_id)
            except UserProfile.DoesNotExist:
                self.stdout.write(self.style.WARNING(f"- Skip (no UserProfile): {user_id}"))
                total_skipped += 1
                continue

            # 画像ファイル列挙
            image_files = sorted(
                [p for p in user_dir.iterdir() if p.is_file() and p.suffix.lower() in ALLOWED_EXTS]
            )

            if not image_files:
                self.stdout.write(f"- No images for {user_id}")
                continue

            self.stdout.write(self.style.NOTICE(f"- User {user_id}: {len(image_files)} files"))

            # 1ユーザー単位でトランザクション
            with transaction.atomic():
                for f in image_files:
                    filename = f.name
                    ext = f.suffix.lower()
                    rel_url = f"/images/{user_id}/{filename}"  # あなたの serve_image に合わせて

                    # 画像スロット index を推測（なければ None）
                    image_index = infer_image_index(user_id, filename)

                    # 既存検索は filename ベースで統一
                    try:
                        asset = ImageAsset.objects.get(user=user, filename=filename)
                        existed = True
                    except ImageAsset.DoesNotExist:
                        asset = None
                        existed = False

                    if not existed:
                        # 新規作成
                        msg = f"  + CREATE: user={user_id} file={filename} index={image_index}"
                        if dry_run:
                            self.stdout.write(self.style.SUCCESS(msg + " [dry-run]"))
                        else:
                            ImageAsset.objects.create(
                                user=user,
                                filename=filename,
                                url=rel_url,
                                image_index=image_index,     # モデルに無ければ削除
                                reviewed=False,
                                moderation_status="pending",
                                report_count=0,
                            )
                        total_new += 1
                    else:
                        # 既存更新（URLやindexズレの修正・オプションでレビューをリセット）
                        changed = False
                        changes = []
                        if getattr(asset, "url", None) != rel_url:
                            changed = True
                            changes.append("url")
                            if not dry_run:
                                asset.url = rel_url

                        # image_index フィールドがある場合のみ同期
                        if hasattr(asset, "image_index") and asset.image_index != image_index:
                            changed = True
                            changes.append("image_index")
                            if not dry_run:
                                asset.image_index = image_index

                        if reset_reviewed:
                            if not dry_run:
                                asset.reviewed = False
                                if hasattr(asset, "reviewed_at"):
                                    asset.reviewed_at = None
                                if hasattr(asset, "reviewed_by"):
                                    asset.reviewed_by = None
                                asset.moderation_status = "pending"
                            changed = True
                            changes.append("reset_reviewed")

                        if changed:
                            msg = f"  ~ UPDATE: user={user_id} file={filename} ({', '.join(changes)})"
                            if dry_run:
                                self.stdout.write(self.style.WARNING(msg + " [dry-run]"))
                            else:
                                # まとめて保存
                                asset.save()
                            total_updated += 1
                        else:
                            total_skipped += 1

        self.stdout.write(self.style.SUCCESS(
            f"Done. created={total_new}, updated={total_updated}, skipped={total_skipped}"
        ))
