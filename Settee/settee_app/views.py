import os
import re
import base64
from urllib.parse import unquote
import json
import time
import requests
import logging
import mimetypes
import shutil
import unicodedata
from typing import Optional
from zoneinfo import ZoneInfo
from datetime import timedelta
from django.db import IntegrityError, transaction, models
from django.conf import settings
from django.contrib.auth.hashers import make_password, check_password
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from django.contrib.auth import authenticate, get_user_model
from django.core import signing
from django.core.validators import EmailValidator
from django.core.exceptions import ValidationError
from django.shortcuts import get_object_or_404
from django.db import IntegrityError
from django.db.models import Prefetch, Count, Subquery, F, Q
from django.http import JsonResponse, FileResponse, Http404
from django.views.decorators.http import require_http_methods
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed
from rest_framework.decorators import api_view, parser_classes, authentication_classes, permission_classes
from django.views.decorators.csrf import csrf_exempt
from rest_framework.permissions import IsAuthenticated, AllowAny, IsAdminUser
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status
from datetime import date, datetime
from .models import UserProfile, Conversation, ConversationMember, ConversationKind, LikeAction, Message, Block, UserTicket, ImageAsset, Report, LikeType, Match, AppStoreTransaction
from .serializers import UserProfileSerializer, LikeActionSerializer, MessageSerializer, ReportSerializer
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asy_padding, ec, rsa
from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
from cryptography.hazmat.backends import default_backend
import pytz

logger = logging.getLogger(__name__)

# ===== ログインボーナス関連のヘルパー関数 =====

# 日本時間のタイムゾーン
JST = pytz.timezone('Asia/Tokyo')

def get_jst_date():
    """現在の日本時間の日付を取得"""
    return timezone.now().astimezone(JST).date()

def check_and_grant_login_bonus(user: UserProfile) -> dict:
    """
    ログインボーナスの判定と付与

    Returns:
        dict: {
            'daily_bonus': int,  # 今回付与されたデイリーボーナス
            'streak_bonus': int,  # 今回付与された連続ログインボーナス
            'consecutive_days': int,  # 現在の連続ログイン日数
            'total_granted': int,  # 合計付与ポイント
            'messages': list[str],  # ユーザーへのメッセージ
        }
    """
    from datetime import timedelta as td

    today = get_jst_date()
    result = {
        'daily_bonus': 0,
        'streak_bonus': 0,
        'consecutive_days': user.consecutive_login_days,
        'total_granted': 0,
        'messages': [],
    }

    # 月初リセット処理
    if user.last_streak_bonus_reset is None or user.last_streak_bonus_reset.month != today.month:
        user.monthly_streak_bonus_count = 0
        user.last_streak_bonus_reset = today

    # 初回ログインまたは前回と異なる日付
    if user.last_login_date is None or user.last_login_date < today:
        # デイリーボーナス付与（1ポイント）
        result['daily_bonus'] = 1
        user.settee_points = (user.settee_points or 0) + 1
        result['messages'].append('ログインボーナス +1pt')

        # 連続ログイン判定
        if user.last_login_date is None:
            # 初回ログイン
            user.consecutive_login_days = 1
        elif user.last_login_date == today - td(days=1):
            # 前日にログインしていた → 連続
            user.consecutive_login_days += 1
        else:
            # 1日以上空いた → リセット
            user.consecutive_login_days = 1
            result['messages'].append('連続ログインが途切れました')

        result['consecutive_days'] = user.consecutive_login_days

        # 7日連続達成で連続ログインボーナス
        if user.consecutive_login_days >= 7:
            # 月間上限チェック（月50pt = 10回まで）
            if user.monthly_streak_bonus_count < 10:
                result['streak_bonus'] = 5
                user.settee_points += 5
                user.monthly_streak_bonus_count += 1
                user.consecutive_login_days = 0  # 連続日数リセット
                result['consecutive_days'] = 0
                result['messages'].append('7日連続ログインボーナス +5pt!')
            else:
                result['messages'].append('今月の連続ログインボーナスは上限に達しました')
                user.consecutive_login_days = 0
                result['consecutive_days'] = 0

        # 最終ログイン日を更新
        user.last_login_date = today
        user.save()

        result['total_granted'] = result['daily_bonus'] + result['streak_bonus']
    else:
        # 同日に再ログイン → ボーナスなし
        result['messages'].append('本日のログインボーナスは受け取り済みです')

    return result

def check_and_grant_match_bonus(user: UserProfile) -> dict:
    """
    マッチングボーナスの判定と付与（マッチング時に呼び出す）

    Returns:
        dict: {
            'bonus': int,  # 付与されたポイント
            'count': int,  # 今月のマッチングボーナス取得回数
            'message': str,
        }
    """
    today = get_jst_date()

    # 月初リセット処理
    if user.last_match_bonus_reset is None or user.last_match_bonus_reset.month != today.month:
        user.monthly_match_bonus_count = 0
        user.last_match_bonus_reset = today

    # 月間上限チェック（月30pt = 10回まで）
    if user.monthly_match_bonus_count < 10:
        user.settee_points = (user.settee_points or 0) + 3
        user.monthly_match_bonus_count += 1
        user.save()
        return {
            'bonus': 3,
            'count': user.monthly_match_bonus_count,
            'message': f'マッチングボーナス +3pt! (今月{user.monthly_match_bonus_count}/10回)',
        }
    else:
        return {
            'bonus': 0,
            'count': user.monthly_match_bonus_count,
            'message': '今月のマッチングボーナスは上限に達しました',
        }

# ===== ログインボーナス関連のヘルパー関数 ここまで =====

@api_view(['POST'])
def register_user(request):
    """
    Flutter から送られてきたユーザーデータを登録
    """
    data = request.data.copy()
    serializer = UserProfileSerializer(data=data)
    
    if serializer.is_valid():
        user = serializer.save()
        return Response({
            "id": user.id,
            "email": user.email,
            "nickname": user.nickname,
            "user_id": user.user_id,
            "message": "登録が完了しました"
        }, status=status.HTTP_201_CREATED)
    
    # ここで必ずエラーを表示
    print("\n\n========== REGISTER ERROR ==========")
    print(serializer.errors)
    print("====================================\n\n")
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

register_user.__name__ = 'register_user'

@api_view(['POST'])
def login_user(request):
    login = request.data.get('login')
    raw_password = request.data.get('password')

    if not login or not raw_password:
        return Response({'detail': 'login と password を指定してください'}, status=400)

    try:
        user = UserProfile.objects.get(user_id=login)
    except UserProfile.DoesNotExist:
        try:
            user = UserProfile.objects.get(email=login)
        except UserProfile.DoesNotExist:
            return Response({'detail': '認証に失敗しました'}, status=400)

    if not check_password(raw_password, user.password):
        return Response({'detail': '認証に失敗しました'}, status=400)

    if user.is_banned:
        return Response({'detail': 'このアカウントは停止されています'}, status=403)

    # ログインボーナス処理
    bonus_result = check_and_grant_login_bonus(user)

    return Response({
        'id': user.id,
        'email': user.email,
        'user_id': user.user_id,
        'nickname': user.nickname,
        'message': 'ログインに成功しました',
        # ログインボーナス情報を追加
        'login_bonus': {
            'daily_bonus': bonus_result['daily_bonus'],
            'streak_bonus': bonus_result['streak_bonus'],
            'consecutive_days': bonus_result['consecutive_days'],
            'total_granted': bonus_result['total_granted'],
            'messages': bonus_result['messages'],
            'current_points': user.settee_points,
        }
    }, status=200)

login_user.__name__ = 'login_user'

@api_view(['POST'])
@parser_classes([MultiPartParser, FormParser])
def upload_user_image(request):
    """
    Flutter から送られた画像を /images/<user_id>/ に保存し、
    ImageAsset を upsert してレビュー状態を pending に戻します。

    保存ファイル名のルール:
      /images/<user_id>/<user_id>_<image_index>.<ext>
    例:
      /images/u123/u123_1.jpg
    """
    print("upload_user_image is called")

    user_id = request.data.get("user_id")
    image_file = request.FILES.get("image")
    image_index_raw = request.data.get("image_index", "1")

    # 入力バリデーション
    if not user_id or not image_file:
        return Response({"detail": "user_id と image を含めてください"}, status=400)

    try:
        image_index = int(image_index_raw)
        if image_index < 1:
            raise ValueError
    except Exception:
        return Response({"detail": "image_index は 1 以上の整数で指定してください"}, status=400)

    # ユーザー存在確認
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({"detail": "指定されたユーザーが存在しません"}, status=404)

    # 保存先ディレクトリ
    upload_dir = os.path.join(settings.BASE_DIR, 'images', user_id)
    os.makedirs(upload_dir, exist_ok=True)

    ext = os.path.splitext(image_file.name)[1]  # 例: ".jpg"
    new_filename = f"{user_id}_{image_index}{ext}"
    file_path = os.path.join(upload_dir, new_filename)

    # 物理保存
    try:
        with open(file_path, 'wb+') as destination:
            for chunk in image_file.chunks():
                destination.write(chunk)
    except Exception as e:
        return Response({"detail": f"ファイル保存中にエラー: {str(e)}"}, status=500)

    # DB 反映（ImageAsset を upsert。差し替え時はレビュー状態を pending に戻す）
    rel_url = f"/images/{user_id}/{new_filename}"
    try:
        with transaction.atomic():
            asset, created = ImageAsset.objects.select_for_update().get_or_create(
                user=user,
                image_index=image_index,
                defaults={
                    "filename": new_filename,
                    "url": rel_url,
                    "reviewed": False,
                    "moderation_status": "pending",
                    "report_count": 0,
                }
            )
            if not created:
                # 既存スロットの差し替え：メタ更新＋レビュー状態をリセット
                asset.filename = new_filename
                asset.url = rel_url
                asset.reviewed = False
                asset.reviewed_at = None
                asset.reviewed_by = None
                asset.moderation_status = "pending"
                asset.save(update_fields=[
                    "filename", "url", "reviewed", "reviewed_at", "reviewed_by", "moderation_status"
                ])
    except Exception as e:
        # 物理保存成功後に DB で失敗した場合
        return Response({"detail": f"DB更新中にエラー: {str(e)}"}, status=500)

    return Response({
        "message": "画像のアップロードに成功しました",
        "path": rel_url,
        "image_index": image_index,
        "reviewed": False,
        "moderation_status": "pending"
    }, status=200)

upload_user_image.__name__ = 'upload_user_image'

def _to_int(s, default=None):
    try:
        return int(s) if s is not None else default
    except (TypeError, ValueError):
        return default

def _parse_mbti(request):
    # '?mbti=INTJ&mbti=ENFP' も '?mbti=INTJ,ENFP' もOKにする
    lst = request.GET.getlist('mbti')
    if not lst:
        csv = request.GET.get('mbti')
        if csv:
            lst = [x.strip() for x in csv.split(',') if x.strip()]
    return {x.upper() for x in lst} if lst else set()

@api_view(['GET'])
def recommended_users(request, user_id):
    # 現在ユーザー
    try:
        current_user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'ユーザーが存在しません'}, status=404)

    # ---- クエリパラメータ ----
    qp_gender      = request.GET.get('gender')            # '男性' / '女性'（省略時は異性）
    age_min        = _to_int(request.GET.get('age_min'))
    age_max        = _to_int(request.GET.get('age_max'))
    height_min     = _to_int(request.GET.get('height_min'))
    height_max     = _to_int(request.GET.get('height_max'))
    occupation     = request.GET.get('occupation')
    mbtis          = _parse_mbti(request)

    offset = _to_int(request.GET.get('offset'), 0)
    limit  = _to_int(request.GET.get('limit'), 10)

    # 対象性別
    if qp_gender in ('男性', '女性'):
        target_gender = qp_gender
    else:
        if current_user.gender == '男性':
            target_gender = '女性'
        elif current_user.gender == '女性':
            target_gender = '男性'
        else:
            return Response({'detail': '性別が不明です'}, status=400)

    # --- ブロック除外（自分→相手 / 相手→自分 の両方向） ---
    blocked_by_me_qs   = Block.objects.filter(blocker=current_user).values('blocked_id')
    blocked_me_qs      = Block.objects.filter(blocked=current_user).values('blocker_id')

    # --- ベースQuerySet（DB側でできる所まで絞る） ---
    qs = (UserProfile.objects
          .filter(
              gender=target_gender,
              match_multiple=current_user.match_multiple,
              is_banned=False,                     # ← BAN 除外
          )
          .exclude(user_id=user_id)                # ← 自分を除外
          .exclude(id__in=Subquery(blocked_by_me_qs))  # ← 自分がブロックした相手
          .exclude(id__in=Subquery(blocked_me_qs))     # ← 相手が自分をブロック
    )

    # 駅エリアの重なり（PostgreSQL ArrayField の overlap 演算子でDB側フィルタ）
    # ※ current_user.selected_area が空ならスキップ
    if current_user.selected_area:
        qs = qs.filter(selected_area__overlap=current_user.selected_area)

    if occupation:
        qs = qs.filter(occupation=occupation)
    if mbtis:
        qs = qs.filter(mbti__in=list(mbtis))

    # ---- 年齢・身長レンジは従来通り Python 側で最終フィルタ ----
    matched_users = []
    for user in qs:
        # 年齢レンジ
        if (age_min is not None) or (age_max is not None):
            a = calculate_age(user.birth_date) if user.birth_date else None
            if a is not None:
                if age_min is not None and a < age_min:
                    continue
                if age_max is not None and a > age_max:
                    continue

        # 身長レンジ（"175cm" などにも対応）
        if (height_min is not None) or (height_max is not None):
            h_raw = getattr(user, 'height', None)
            h = None
            if h_raw is not None:
                if isinstance(h_raw, (int, float)):
                    h = int(h_raw)
                else:
                    import re
                    m = re.search(r'(\d{2,3})', str(h_raw))
                    if m:
                        h = int(m.group(1))
            if h is not None:
                if height_min is not None and h < height_min:
                    continue
                if height_max is not None and h > height_max:
                    continue

        matched_users.append(user)

    # ページング
    paged_users = matched_users[offset:offset + limit]

    # レスポンス
    results = []
    for user in paged_users:
        image_dir = f"/images/{user.user_id}/"
        try:
            base = os.path.join(settings.BASE_DIR, 'images', user.user_id)
            files = os.listdir(base)
            image_file = next(iter(files))
            image_url = image_dir + image_file
        except Exception:
            image_url = ""

        results.append({
            'user_id': user.user_id,
            'nickname': user.nickname,
            'age': calculate_age(user.birth_date),
            'selected_area': user.selected_area,
            'gender': user.gender,
            'mbti': user.mbti,
            'drinking': user.drinking,
            'zodiac': user.zodiac,
            'university': user.university,
            'smoking': user.smoking,
            'seeking': user.seeking,
            'preference': user.preference,
            'available_dates': user.available_dates,
            'height': getattr(user, 'height', None),
            'image_url': image_url,
        })

    return Response(results, status=200)

def calculate_age(birth_date):
    from datetime import date
    today = date.today()
    return today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))

LIKE_NORMAL = 0
LIKE_SUPER = 1
LIKE_TREAT = 2
LIKE_MESSAGE = 3

def _entitlements_payload(user, now):
    """
    フロント同期用の最新権限状態を返す。
    - UserProfile.get_entitlements() をベースにしつつ、
      既存フロントが参照している互換キーも含めて返す。
    """
    # アクセス時に枠を正しく整える（Normal 12h / VIP 月次）
    user.ensure_quotas_now(save=True)

    ent = user.get_entitlements()  # モデル実装済みの一括集約
    iso = lambda dt: dt.isoformat() if dt else None

    return {
        # そのまま返す集約済み情報
        **ent,

        # 追加で欲しい基本情報
        'settee_points': int(getattr(user, 'settee_points', 0) or 0),

        # 既存フロント互換キー（必要に応じて利用）
        'settee_plus_until': iso(getattr(user, 'settee_plus_until', None)),
        'boost_until':       iso(getattr(user, 'boost_until', None)),
        'private_mode_until': iso(getattr(user, 'private_mode_until', None)),
        'refine_unlocked':   bool(getattr(user, 'refine_unlocked', False)),
        'can_refine':        bool(getattr(user, 'refine_unlocked', False)),  # 互換エイリアス
        'server_time':       now.isoformat(),

        # “can_*”系はクレジットの有無で算出（Treatも追加）
        'can_message_like':  int(ent.get('message_like_credits', 0) or 0) > 0,
        'can_super_like':    int(ent.get('super_like_credits', 0)  or 0) > 0,
        'can_treat_like':    int(ent.get('treat_like_credits', 0)  or 0) > 0,
    }

@api_view(['POST'])
def like_user(request):
    """
    POST JSON:
      - sender   : 送信者 user_id
      - receiver : 受信者 user_id
      - like_type: 0=通常, 1=スーパー, 2=ごちそう, 3=メッセージ
      - message  : like_type=3 のとき必須
    仕様:
      - モデルの ensure_quotas_now()/consume_like() を使って残数/枠を厳密管理
      - 上書きポリシー: 既存が「通常」のときだけ上書き可（通常→他種）。それ以外は上書き不可
      - Treat は Plus制限ではなく「クレジットの有無」で判定（VIP/月次・チケット加算対応）
    """
    sender_user_id   = request.data.get('sender')
    receiver_user_id = request.data.get('receiver')
    like_type_raw    = request.data.get('like_type')
    message_text     = (request.data.get('message') or '').strip()

    # 基本バリデーション
    try:
        like_type = int(like_type_raw)
    except (TypeError, ValueError):
        return Response({'error': 'like_type は整数で指定してください', 'code': 'INVALID_LIKE_TYPE'}, status=400)

    if like_type not in (LIKE_NORMAL, LIKE_SUPER, LIKE_TREAT, LIKE_MESSAGE):
        return Response({'error': '不正な like_type です', 'code': 'INVALID_LIKE_TYPE'}, status=400)

    if not sender_user_id or not receiver_user_id:
        return Response({'error': 'sender / receiver は必須です', 'code': 'MISSING_PARAMS'}, status=400)

    if sender_user_id == receiver_user_id:
        return Response({'error': '自分自身には送信できません', 'code': 'SELF_LIKE_FORBIDDEN'}, status=400)

    # Message Like では本文必須
    if like_type == LIKE_MESSAGE and not message_text:
        return Response({'error': 'メッセージLikeでは message は必須です', 'code': 'MESSAGE_REQUIRED'}, status=400)

    now = timezone.now()

    try:
        with transaction.atomic():
            # 送信者はロックして残数を原子的に消費する
            sender   = UserProfile.objects.select_for_update().get(user_id=sender_user_id)
            receiver = UserProfile.objects.get(user_id=receiver_user_id)

            if getattr(sender, 'is_banned', False):
                return Response({'error': '利用制限中のため送信できません', 'code': 'SENDER_BANNED'}, status=403)

            # 参照時点で枠を整える（Normal 12h / VIP 月次）
            sender.ensure_quotas_now(save=True)

            # 既存 Like を取得（ユニーク制約につき最大1件）
            existing = LikeAction.objects.select_for_update().filter(sender=sender, receiver=receiver).first()

            # 上書きポリシー判定
            will_create  = False
            will_upgrade = False     # 既存 NORMAL → 他種
            will_change  = False     # DBのフィールドが変わるか（消費の判定とは別）

            if existing is None:
                will_create = True
                will_change = True
            else:
                if existing.like_type == LIKE_NORMAL:
                    if like_type == LIKE_NORMAL:
                        # 同じ通常Likeの再送は状態不変（消費もしない）
                        will_create = False
                        will_upgrade = False
                        will_change = False
                    else:
                        # 通常→他種に“昇格”可
                        will_create = False
                        will_upgrade = True
                        will_change = True
                else:
                    # 既に通常以外 → 上書き不可（同種の再送はOKだが状態不変）
                    if like_type != existing.like_type:
                        return Response({'error': '既にLike済みです（上書き不可）', 'code': 'ALREADY_LIKED'}, status=409)
                    will_create = False
                    will_upgrade = False
                    will_change = False  # 同種再送は状態不変

            # 残数消費が必要かどうか（“新規”または“通常→他種”時に消費）
            should_consume = will_create or will_upgrade
            if should_consume:
                ok = sender.consume_like(like_type, save=True)
                if not ok:
                    # タイプ別エラー
                    if like_type == LIKE_NORMAL:
                        return Response({
                            'error': '通常Likeの残数がありません',
                            'code': 'NO_NORMAL_LIKE_REMAINING',
                            'reset_at': sender.normal_like_reset_at.isoformat() if sender.normal_like_reset_at else None
                        }, status=400)
                    elif like_type == LIKE_SUPER:
                        return Response({'error': 'スーパーライクの残数がありません', 'code': 'NO_SUPER_LIKE_CREDITS'}, status=400)
                    elif like_type == LIKE_TREAT:
                        return Response({'error': 'ごちそうライクの残数がありません', 'code': 'NO_TREAT_LIKE_CREDITS'}, status=400)
                    elif like_type == LIKE_MESSAGE:
                        return Response({'error': 'メッセージライクの残数がありません', 'code': 'NO_MESSAGE_LIKE_CREDITS'}, status=400)

            # 永続化
            if will_create:
                obj = LikeAction.objects.create(
                    sender=sender, receiver=receiver, like_type=like_type,
                    message=message_text if like_type == LIKE_MESSAGE else None,
                    message_sent_at=now if like_type == LIKE_MESSAGE else None,
                )
                status_code = 201
            else:
                obj = existing or LikeAction(sender=sender, receiver=receiver, like_type=LIKE_NORMAL)
                if will_upgrade:
                    obj.like_type = like_type
                    if like_type == LIKE_MESSAGE:
                        obj.message = message_text
                        obj.message_sent_at = now
                    obj.save(update_fields=['like_type', 'message', 'message_sent_at', 'updated_at'])
                # 状態不変（同種再送 or 通常の再送）の場合は保存不要
                status_code = 200

    except UserProfile.DoesNotExist:
        return Response({'error': '指定されたユーザーが存在しません', 'code': 'USER_NOT_FOUND'}, status=400)

    # 成功レスポンス（最新エンタイトルメントを同梱）
    return Response({
        'id': obj.id,
        'like_type': obj.like_type,
        'created': (status_code == 201),
        'entitlements': _entitlements_payload(sender, now),
    }, status=status_code)

@api_view(['GET'])
def get_user_profile(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    data = {
        'user_id': user.user_id,
        'phone': user.phone,
        'nickname': user.nickname,
        'email': user.email,
        'birth_date': user.birth_date,
        'gender': user.gender,
        'selected_area': user.selected_area,
        'match_multiple': user.match_multiple,
        'occupation': user.occupation,
        'university': user.university,
        'blood_type': user.blood_type,
        'height': user.height,
        'drinking': user.drinking,
        'smoking': user.smoking,
        'zodiac': user.zodiac,
        'mbti': user.mbti,
        'seeking': user.seeking,
        'preference': user.preference
    }

    return Response(data, status=200)


@api_view(['GET'])
def popular_users(request, current_user_id):
    try:
        current_user = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    opposite_gender = '男性' if current_user.gender == '女性' else '女性'

    # 自分がブロックした相手
    blocked_qs = Block.objects.filter(blocker=current_user).values('blocked_id')

    # 直近1週間に自分がLike送信した相手（receiver_id）
    week_ago = timezone.now() - timedelta(days=7)
    liked_recent_qs = (LikeAction.objects
                       .filter(sender=current_user, created_at__gte=week_ago)
                       .values('receiver_id'))

    users = (
        UserProfile.objects
        .filter(gender=opposite_gender, is_banned=False)
        .exclude(user_id=current_user_id)                 # 自分を除外
        .exclude(id__in=Subquery(blocked_qs))             # 自分がブロックした相手を除外
        .exclude(id__in=Subquery(liked_recent_qs))        # ★ 過去1週間にLike済みの相手を除外
        .annotate(like_count=Count('received_likes'))
        .order_by('-like_count', '-id')[:10]
    )

    data = [{'user_id': u.user_id, 'nickname': u.nickname} for u in users]
    return Response(data, status=200)


@api_view(['GET'])
def recent_users(request, current_user_id):
    try:
        current_user = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    opposite_gender = '男性' if current_user.gender == '女性' else '女性'

    blocked_qs = Block.objects.filter(blocker=current_user).values('blocked_id')

    week_ago = timezone.now() - timedelta(days=7)
    liked_recent_qs = (LikeAction.objects
                       .filter(sender=current_user, created_at__gte=week_ago)
                       .values('receiver_id'))

    users = (
        UserProfile.objects
        .filter(gender=opposite_gender, is_banned=False)
        .exclude(user_id=current_user_id)
        .exclude(id__in=Subquery(blocked_qs))
        .exclude(id__in=Subquery(liked_recent_qs))        # ★ 過去1週間にLike済みの相手を除外
        .order_by('-id')[:10]
    )

    data = [{'user_id': u.user_id, 'nickname': u.nickname} for u in users]
    return Response(data, status=200)

@api_view(['GET'])
def matched_users(request, current_user_id):
    try:
        me = UserProfile.objects.get(user_id=current_user_id)

        # --- ブロック集合（片/両方向） ---
        blocked_outgoing = set(
            Block.objects.filter(blocker=me)
            .values_list('blocked__user_id', flat=True)
        )
        blocked_incoming = set(
            Block.objects.filter(blocked=me)
            .values_list('blocker__user_id', flat=True)
        )
        blocked_any = blocked_outgoing | blocked_incoming

        # --- 相互Like（ブロック除外） ---
        sent = set(
            LikeAction.objects.filter(sender=me)
            .exclude(receiver__user_id__in=blocked_any)
            .values_list('receiver__user_id', flat=True)
        )
        received = set(
            LikeAction.objects.filter(receiver=me)
            .exclude(sender__user_id__in=blocked_any)
            .values_list('sender__user_id', flat=True)
        )
        mutual_like_ids = sent & received

        # --- ダブル会話の「初期ペア相手」だけを抽出 ---
        double_partner_ids = set()
        double_convs = (
            Conversation.objects
            .filter(
                kind=ConversationKind.DOUBLE,
                members__user=me,
                members__left_at__isnull=True,
            )
            .select_related('matched_pair_a', 'matched_pair_b')
            .distinct()
        )

        for conv in double_convs:
            a = getattr(conv.matched_pair_a, 'user_id', None)
            b = getattr(conv.matched_pair_b, 'user_id', None)

            # 初期ペアのどちらかがブロック関係ならスキップ
            if (a in blocked_any) or (b in blocked_any):
                continue

            if a == current_user_id and b:
                double_partner_ids.add(b)
            elif b == current_user_id and a:
                double_partner_ids.add(a)
            else:
                # 自分が招待参加（a/b に含まれない）でも、
                # 一覧は“初期ペア”のどちらか1名（≠自分）だけを代表として載せる
                if a and a != current_user_id:
                    double_partner_ids.add(a)
                elif b and b != current_user_id:
                    double_partner_ids.add(b)

        # --- 最終候補 = 相互Like ∪ ダブル初期ペア相手（共同参加者は含めない） ---
        partner_ids = (mutual_like_ids | double_partner_ids) - blocked_any
        partner_ids.discard(current_user_id)

        users = (
            UserProfile.objects
            .filter(user_id__in=partner_ids)
            .only('user_id', 'nickname')
            .order_by('nickname')
        )
        result = [{'user_id': u.user_id, 'nickname': u.nickname} for u in users]
        return Response(result, status=200)

    except UserProfile.DoesNotExist:
        # 未登録などは空配列
        return Response([], status=200)
    except Exception as e:
        return Response({'error': str(e)}, status=500)
    
@api_view(['GET'])
def get_unread_matches(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)
    
    # 未読マッチのみ取得（userオブジェクトを使う）
    unread_matches = Match.objects.filter(
        Q(user_lower_id=user, lower_user_seen=False) |
        Q(user_higher_id=user, higher_user_seen=False)
    ).select_related('user_lower_id', 'user_higher_id').order_by('-matched_at')
    
    # QuerySetをシリアライズ
    matches_data = []
    for match in unread_matches:
        # パートナーを手動で取得
        if match.user_lower_id == user:
            partner = match.user_higher_id
        else:
            partner = match.user_lower_id
            
        matches_data.append({
            'match_id': match.id,
            'matched_at': match.matched_at,
            'partner': {        
                'user_id': partner.user_id,
                'nickname': partner.nickname,
            }
        })
    
    return Response({
        'unread_count': unread_matches.count(),
        'matches': matches_data
    }, status=200)

@api_view(['POST'])
def match(request):
    me_id = request.data.get('me')
    other_id = request.data.get('other')
    
    if not me_id or not other_id:
        return Response({'error': 'me と other は必須です'}, status=400)
    
    try: 
        me = UserProfile.objects.get(user_id=me_id)
        other = UserProfile.objects.get(user_id=other_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)
    
    # 同じユーザー同士のマッチを防止
    if me.id == other.id:
        return Response({'error': '自分自身とはマッチできません'}, status=400)
    
    # 既存のマッチをチェック
    try:
        Match.get_match(me, other)
        return Response({'error': '既にマッチしています'}, status=400)
    except Match.DoesNotExist:
        pass  # マッチが存在しない場合は続行

    match = Match.create_match(me, other)

    # マッチング成立時に両ユーザーにマッチングボーナス付与
    bonus_me = check_and_grant_match_bonus(me)
    check_and_grant_match_bonus(other)  # 相手にもボーナス付与

    return Response({
        'message': 'マッチングしました',
        'match_id': match.id,
        'matched_at': match.matched_at,
        # マッチングボーナス情報を追加
        'match_bonus': {
            'bonus': bonus_me['bonus'],
            'message': bonus_me['message'],
        }
    }, status=201)

@api_view(['PATCH'])
def update_read_match(request, user_id, other_id):
    try:
        # 両方のユーザーを取得
        user = UserProfile.objects.get(user_id=user_id)
        other = UserProfile.objects.get(user_id=other_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)
    
    # Match.get_match() を使う（自動的に順序を正規化）
    try:
        match = Match.get_match(user, other)
    except Match.DoesNotExist:
        return Response({'error': 'マッチが見つかりません'}, status=404)
    
    # 既読状態を更新
    match.mark_seen_by(user)
    
    return Response({
        'message': '既読にしました',
        'match_id': match.id
    }, status=200)

# ------------- 共通: DM 会話を作る/見つける -------------
def ensure_dm_conversation(user_a: UserProfile, user_b: UserProfile) -> Conversation:
    # 2人とも入っている DM を再利用（なければ作成）
    conv = (Conversation.objects
            .filter(kind=ConversationKind.DM, members__user=user_a)
            .filter(members__user=user_b)
            .distinct()
            .first())
    if conv:
        return conv

    conv = Conversation.objects.create(kind=ConversationKind.DM, created_by=user_a,
                                       matched_pair_a=user_a, matched_pair_b=user_b)
    ConversationMember.objects.bulk_create([
        ConversationMember(conversation=conv, user=user_a, role='owner'),
        ConversationMember(conversation=conv, user=user_b, role='owner'),
    ])
    return conv

# ------------- 既存URL互換: 1:1 送信（内部的には会話に保存） -------------
@api_view(['POST'])
def send_message(request):
    """
    互換API: body { sender, receiver, text }
    → DM Conversation を ensure して、Message を会話に保存
    """
    sender_id = (request.data.get('sender') or '').strip()
    receiver_id = (request.data.get('receiver') or '').strip()
    text = (request.data.get('text') or '').strip()

    if not sender_id or not receiver_id or not text:
        return Response({'error': 'sender / receiver / text は必須です'}, status=400)
    if sender_id == receiver_id:
        return Response({'error': '自分宛には送信できません'}, status=400)

    try:
        sender = UserProfile.objects.get(user_id=sender_id)
        receiver = UserProfile.objects.get(user_id=receiver_id)
    except UserProfile.DoesNotExist:
        return Response({'error': '送信者または受信者が存在しません'}, status=400)

    with transaction.atomic():
        conv = ensure_dm_conversation(sender, receiver)
        msg = Message.objects.create(conversation=conv, sender=sender, text=text)

    # 互換レスポンス（receiver はDBに持たせていないが応答には含める）
    return Response({
        'id': msg.id,
        'conversation': conv.id,
        'sender': sender.user_id,
        'receiver': receiver.user_id,
        'text': msg.text,
        'timestamp': msg.created_at.isoformat(),
    }, status=status.HTTP_201_CREATED)

# ------------- 既存URL互換: 1:1 履歴取得（内部的には会話から読む） -------------
@api_view(['GET'])
def get_messages(request, user1_id, user2_id):
    try:
        u1 = UserProfile.objects.get(user_id=user1_id)
        u2 = UserProfile.objects.get(user_id=user2_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    conv = (Conversation.objects
            .filter(kind=ConversationKind.DM, members__user=u1)
            .filter(members__user=u2)
            .distinct()
            .first())
    
    is_active_member = ConversationMember.objects.filter(
        conversation=conv, user=u1, left_at__isnull=True
    ).exists()
    if not conv:
        return Response([], status=200)

    msgs = (Message.objects
            .select_related('sender')
            .filter(conversation=conv)
            .order_by('created_at'))

    out = [{
        'id': m.id,
        'conversation': conv.id,
        'sender': getattr(m.sender, 'user_id', None),
        'receiver': user2_id if getattr(m.sender, 'user_id', None) == user1_id else user1_id,
        'text': m.text,
        'timestamp': m.created_at.isoformat(),
    } for m in msgs]
    return Response(out, status=200)

@api_view(['GET'])
def received_likes(request, user_id: str):
    """
    GET /likes/received/<user_id>/?paid_only=1&since=ISO8601&limit=500&senders=a,b,c

    - paid_only=1        : 通常Like(0)を除外（= 有料Likeのみ）
    - since=ISO8601      : “更新時刻(updated_at)” 以降で絞り込み（昇格も拾える）
    - limit=<int>        : 返却件数（既定500 / 最大2000）
    - senders=a,b,c      : 送信者(user_id)での絞り込み（任意）
    応答:
      [
        {
          "sender_id": "u_foo",
          "like_type": 1,
          "message": "（MESSAGEの時のみ）",
          "created_at": "...",
          "updated_at": "..."
        },
        ...
      ]
    """
    from .models import UserProfile, LikeAction, LikeType  # 適宜パスを調整

    # 受信者の存在確認
    try:
        receiver = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=status.HTTP_404_NOT_FOUND)

    # クエリパラメータ
    paid_only = str(request.query_params.get('paid_only', '0')).lower() in ('1', 'true', 'yes')
    limit_raw = request.query_params.get('limit', '500')
    try:
        limit = max(1, min(int(limit_raw), 2000))
    except ValueError:
        limit = 500

    since_str = request.query_params.get('since')
    since_dt = parse_datetime(since_str) if since_str else None
    if since_dt and timezone.is_naive(since_dt):
        since_dt = timezone.make_aware(since_dt, timezone.utc)

    senders_param = request.query_params.get('senders')
    sender_ids = [s for s in senders_param.split(',') if s] if senders_param else None

    # クエリ構築
    qs = LikeAction.objects.select_related('sender').filter(receiver=receiver)
    if paid_only:
        qs = qs.exclude(like_type=LikeType.NORMAL)
    if since_dt:
        qs = qs.filter(updated_at__gte=since_dt)  # 昇格も拾うため updated_at 基準が◎
    if sender_ids:
        qs = qs.filter(sender__user_id__in=sender_ids)

    qs = qs.order_by('-updated_at')[:limit]

    data = []
    for o in qs:
        data.append({
            'sender_id':  getattr(o.sender, 'user_id', None) or 'DELETED',
            'like_type':  int(o.like_type),
            'message':    (o.message if o.like_type == LikeType.MESSAGE else None),
            'created_at': o.created_at.isoformat(),
            'updated_at': o.updated_at.isoformat(),
        })

    return Response(data, status=status.HTTP_200_OK)

# ------------- 新規: DoubleMatch の開始（相互マッチ等で呼ぶ） -------------
@api_view(['POST'])
def start_double_match(request):
    """
    body: {"user_a":"u_me","user_b":"u_you"}
    2人の DoubleMatch 会話を新規作成（既存があれば再利用）
    """
    ua = (request.data.get('user_a') or '').strip()
    ub = (request.data.get('user_b') or '').strip()
    if not ua or not ub or ua == ub:
        return Response({'error': 'INVALID_USERS'}, status=400)

    try:
        a = UserProfile.objects.get(user_id=ua)
        b = UserProfile.objects.get(user_id=ub)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=404)

    with transaction.atomic():
        conv = (Conversation.objects
                .filter(kind=ConversationKind.DOUBLE, members__user=a)
                .filter(members__user=b)
                .distinct()
                .order_by('-id')
                .first())
        if conv is None:
            conv = Conversation.objects.create(
                kind=ConversationKind.DOUBLE,
                created_by=a, matched_pair_a=a, matched_pair_b=b)
            ConversationMember.objects.bulk_create([
                ConversationMember(conversation=conv, user=a, role='owner'),
                ConversationMember(conversation=conv, user=b, role='owner'),
            ])

    return Response({
        'id': conv.id, 'kind': conv.kind,
        'members': [m.user.user_id for m in conv.members.select_related('user')],
    }, status=201)

# ------------- 新規: 招待（ユーザIDでメンバー追加） -------------
@api_view(['POST'])
def invite_to_conversation(request):
    """
    body: {"conversation_id":123, "inviter":"u_me", "invitee":"u_friend"}
    """
    cid = request.data.get('conversation_id')
    inviter_id = (request.data.get('inviter') or '').strip()
    invitee_id = (request.data.get('invitee') or '').strip()
    if not cid or not inviter_id or not invitee_id:
        return Response({'error': 'MISSING_PARAMS'}, status=400)

    try:
        cid = int(cid)
    except (TypeError, ValueError):
        return Response({'error': 'INVALID_CONVERSATION_ID'}, status=400)

    # ユーザー解決
    try:
        inviter = UserProfile.objects.get(user_id=inviter_id)
        invitee = UserProfile.objects.get(user_id=invitee_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=404)

    try:
        with transaction.atomic():
            # 会話ロック
            conv = Conversation.objects.select_for_update().get(id=cid)
            if conv.kind != ConversationKind.DOUBLE:
                return Response({'error': 'WRONG_KIND'}, status=400)

            # 招待者は有効メンバーであること
            if not ConversationMember.objects.filter(
                conversation=conv, user=inviter, left_at__isnull=True
            ).exists():
                return Response({'error': 'FORBIDDEN'}, status=403)

            # 既存の有効メンバーをロック付きで取得
            active_qs = ConversationMember.objects.select_for_update().filter(
                conversation=conv, left_at__isnull=True
            )
            active_ids = list(active_qs.values_list('user_id', flat=True))

            # 既に invitee が在籍しているか
            invitee_is_already_member = invitee.id in active_ids

            # 上限チェック（すでに在籍していればOK、未在籍なら空きが必要）
            MAX_MEMBERS = 4
            if not invitee_is_already_member and active_qs.count() >= MAX_MEMBERS:
                return Response({'error': 'MEMBER_LIMIT_REACHED'}, status=409)

            # ブロック関係の拒否（招待者↔招待客、既存メンバー↔招待客 のいずれかがブロック）
            if Block.objects.filter(
                models.Q(blocker=inviter, blocked=invitee) |
                models.Q(blocker=invitee, blocked=inviter) |
                models.Q(blocker__in=active_ids, blocked=invitee.id) |
                models.Q(blocker=invitee.id, blocked__in=active_ids)
            ).exists():
                return Response({'error': 'BLOCKED_RELATION'}, status=403)

            # 追加 or 復帰（★ invited_by を記録）
            cm, created = ConversationMember.objects.get_or_create(
                conversation=conv, user=invitee,
                defaults={'role': 'member', 'invited_by': inviter}
            )
            updates = []
            if cm.left_at is not None:
                cm.left_at = None
                updates.append('left_at')
            if cm.invited_by_id is None:
                cm.invited_by = inviter
                updates.append('invited_by')
            if updates:
                cm.save(update_fields=updates)

            # 返却：誰が誰を招待したかが分かるよう invited_by を含める
            members_qs = conv.members.select_related('user', 'invited_by').filter(left_at__isnull=True)
            members = [{
                'user_id':    m.user.user_id,
                'nickname':   m.user.nickname,
                'role':       m.role,
                'invited_by': (m.invited_by.user_id if m.invited_by_id else None),
            } for m in members_qs]

        return Response({'id': conv.id, 'kind': conv.kind, 'members': members}, status=200)

    except Conversation.DoesNotExist:
        return Response({'error': 'CONV_NOT_FOUND'}, status=404)
    except Exception:
        return Response({'error': 'SERVER_ERROR'}, status=500)

# ------------- 新規: 会話一覧（ユーザ別） -------------
@api_view(['GET'])
def list_conversations_for_user(request, user_id: str):
    """
    会話一覧（自分が在室の会話のみ）
    - members は left_at IS NULL の在室メンバーだけ返す
    - 各メンバー: user_id / nickname / role / invited_by（user_id）/ joined_at / left_at(None)
    - matched_pair: [user_id_a, user_id_b] を常に含める（double/dm 共通）
    - ブロック相手を含む会話は除外（片方向でも除外）
    - 並び順: last_message_at desc → updated_at desc → id desc
    """
    # 自分の存在確認
    try:
        me = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=404)

    # ブロック集合（片方向でも）
    blocked_outgoing = set(Block.objects
                           .filter(blocker=me)
                           .values_list('blocked__user_id', flat=True))
    blocked_incoming = set(Block.objects
                           .filter(blocked=me)
                           .values_list('blocker__user_id', flat=True))
    blocked_any = blocked_outgoing | blocked_incoming

    # 会話メンバー（自分が在室）をベースに、会話と在室メンバーを一括プリフェッチ
    # matched_pair_* は select_related で同時取得
    base_qs = (ConversationMember.objects
               .select_related(
                   'conversation',
                   'conversation__matched_pair_a',
                   'conversation__matched_pair_b',
               )
               .filter(user=me, left_at__isnull=True)
               # ブロック相手を含む会話は一覧から除外
               .exclude(conversation__members__user__user_id__in=blocked_any)
               .order_by('-conversation__last_message_at',
                         '-conversation__updated_at',
                         '-conversation__id')
               .distinct())

    # 会話の在室メンバーを事前に取得（user / invited_by を同時に）
    members_qs = (ConversationMember.objects
                  .filter(left_at__isnull=True)
                  .select_related('user', 'invited_by')
                  .order_by('joined_at', 'id'))

    mems = base_qs.prefetch_related(
        Prefetch('conversation__members', queryset=members_qs)
    )

    def _iso(dt):
        return dt.isoformat() if dt else None

    data = []
    for m in mems:
        conv = m.conversation

        # matched_pair（常に2要素 or None を返す）
        mp_a = getattr(conv.matched_pair_a, 'user_id', None)
        mp_b = getattr(conv.matched_pair_b, 'user_id', None)
        matched_pair = [x for x in (mp_a, mp_b) if x]

        # 在室メンバーを詳細でシリアライズ
        members_payload = []
        for cm in conv.members.all():  # Prefetch 済み（left_at NULL のみ）
            members_payload.append({
                'user_id'   : cm.user.user_id if cm.user_id else None,
                'nickname'  : cm.user.nickname if cm.user_id else None,
                'role'      : cm.role or 'member',
                'invited_by': (cm.invited_by.user_id if cm.invited_by_id else None),
                'joined_at' : _iso(cm.joined_at),
                'left_at'   : None,  # 在室のみ返しているため常に None
            })

        data.append({
            'id'             : conv.id,
            'kind'           : conv.kind,                 # 'dm' | 'double' | 'group'
            'title'          : conv.title or '',
            'matched_pair'   : matched_pair,              # ★ これをフロントで相手判定に使用
            'members'        : members_payload,           # ★ invited_by/role を含む
            'updated_at'     : _iso(conv.updated_at),
            'last_message_at': _iso(conv.last_message_at),
        })

    return Response(data, status=200)

# ------------- 新規: 会話に送信/取得 -------------
@api_view(['POST'])
def send_message_to_conversation(request, conversation_id: int):
    """
    body: { "sender":"u_me", "text":"こんにちは" }
    """
    text = (request.data.get('text') or '').trim() if hasattr(str, 'trim') else (request.data.get('text') or '').strip()
    sender_id = (request.data.get('sender') or '').strip()
    if not sender_id or not text:
        return Response({'error': 'MISSING_PARAMS'}, status=400)

    try:
        conv = Conversation.objects.get(id=conversation_id)
        sender = UserProfile.objects.get(user_id=sender_id)
    except (Conversation.DoesNotExist, UserProfile.DoesNotExist):
        return Response({'error': 'NOT_FOUND'}, status=404)

    if not ConversationMember.objects.filter(conversation=conv, user=sender, left_at__isnull=True).exists():
        return Response({'error': 'FORBIDDEN'}, status=403)

    msg = Message.objects.create(conversation=conv, sender=sender, text=text)
    return Response({
        'id': msg.id, 'conversation': conv.id, 'sender': sender.user_id,
        'text': msg.text, 'timestamp': msg.created_at.isoformat()
    }, status=201)

@api_view(['GET'])
def get_conversation_messages(request, conversation_id: int):
    try:
        conv = Conversation.objects.get(id=conversation_id)
    except Conversation.DoesNotExist:
        return Response({'error': 'CONV_NOT_FOUND'}, status=404)

    msgs = conv.messages.select_related('sender').order_by('created_at')
    out = [{
        'id': m.id,
        'sender': getattr(m.sender, 'user_id', None),
        'text': m.text,
        'timestamp': m.created_at.isoformat(),
    } for m in msgs]
    return Response(out, status=200)

@api_view(['GET'])
def get_available_dates(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
        user.clean_available_dates()
        return Response({
            'available_dates': [d.isoformat() for d in user.available_dates]
        })
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found.'}, status=404)


@api_view(['POST'])
def update_available_dates(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
        dates = request.data.get('available_dates', [])
        parsed_dates = []
        for d in dates:
            parsed_dates.append(date.fromisoformat(d))
        user.available_dates = parsed_dates
        user.save()
        return Response({'message': 'Available dates updated successfully.'})
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found.'}, status=404)
    except Exception as e:
        return Response({'error': str(e)}, status=400)
    
@api_view(['GET'])
def get_selected_areas(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
        return Response({'selected_area': user.selected_area}, status=200)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

@api_view(['POST'])
def update_selected_areas(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
        areas = request.data.get('selected_area', [])
        if not isinstance(areas, list):
            return Response({'error': 'selected_areaはリストである必要があります'}, status=400)
        user.selected_area = areas
        user.save()
        return Response({'message': 'Selected areas updated successfully.'})
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found.'}, status=404)

@api_view(['POST'])
def add_settee_points(request):
    try:
        user = UserProfile.objects.get(user_id=request.data.get('user_id'))
        user.settee_points += request.data.get('amount')
        user.save()
        return Response({'message': 'ポイントが作成されました'}, status=200)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

@api_view(['POST'])
def update_match_multiple(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    match_multiple = request.data.get('match_multiple')
    if isinstance(match_multiple, bool):
        user.match_multiple = match_multiple
        user.save()
        return Response({'message': '更新成功'}, status=200)
    else:
        return Response({'error': 'bool値が必要です'}, status=400)
    
@api_view(['PATCH'])
def update_user_profile(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=status.HTTP_404_NOT_FOUND)

    print("=== リクエストデータ ===")
    print(request.data)

    serializer = UserProfileSerializer(user, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response({'message': 'プロフィールを更新しました'}, status=status.HTTP_200_OK)
    else:
        print("=== バリデーションエラー ===")
        print(serializer.errors)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['GET'])
def health_check(request):
    return JsonResponse({'status': 'ok'}, status=200)

@api_view(['GET'])
def serve_image(request, user_id, filename):
    # 任意の画像保存ディレクトリ（MEDIA_ROOT または固定パス）
    image_path = os.path.join(settings.MEDIA_ROOT, user_id, filename)
    if not os.path.exists(image_path):
        raise Http404("画像が存在しません")
    
    return FileResponse(open(image_path, 'rb'))

@api_view(['DELETE', 'POST'])  # DELETE を推奨。POST も許可（スケーラビリティ上）
def delete_account(request, user_id):
    """
    本人確認（password）後、ユーザーと関連データを削除します。
    - ユーザー直下の画像ディレクトリ（/images/<user_id>/）も削除
    - LikeAction, Message は on_delete=CASCADE で自動削除
    """
    # 入力取得（JSON or form）
    raw_password = request.data.get('password') or request.POST.get('password')
    confirm     = (request.data.get('confirm') or request.POST.get('confirm') or '').strip().lower()

    if not raw_password:
        return Response({'error': 'password を指定してください'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=status.HTTP_404_NOT_FOUND)

    # （任意）二重確認の文字列 "delete" などを要求する場合
    # if confirm != 'delete':
    #     return Response({'error': 'confirm に "delete" を指定してください'}, status=400)

    # パスワード確認
    if not check_password(raw_password, user.password):
        return Response({'error': 'パスワードが正しくありません'}, status=status.HTTP_400_BAD_REQUEST)

    # 画像ディレクトリ削除（存在しない場合は無視）
    try:
        img_dir = os.path.join(settings.BASE_DIR, 'images', user.user_id)
        if os.path.isdir(img_dir):
            shutil.rmtree(img_dir)
    except Exception as e:
        # 画像削除に失敗しても、ユーザー削除は続行する方針
        print(f"[WARN] Failed to delete image dir: {e}")

    # ユーザー削除（関連 LikeAction / Message は CASCADE）
    user.delete()

    return Response({'message': 'アカウントを削除しました'}, status=status.HTTP_200_OK)

@api_view(['POST'])
def block_user(request):
    blocker_id = request.data.get('blocker')
    blocked_id = request.data.get('blocked')
    if not blocker_id or not blocked_id:
        return Response({'error': 'blocker と blocked を指定してください'}, status=400)
    if blocker_id == blocked_id:
        return Response({'error': '自分自身はブロックできません'}, status=400)

    try:
        blocker = UserProfile.objects.get(user_id=blocker_id)
        blocked = UserProfile.objects.get(user_id=blocked_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    Block.objects.get_or_create(blocker=blocker, blocked=blocked)

    # 片方向のみ削除（blocker→blocked の Like だけ削除）
    LikeAction.objects.filter(sender=blocker, receiver=blocked).delete()

    now = timezone.now()
    ConversationMember.objects.filter(
        user=blocker,
        left_at__isnull=True,
        conversation__members__user=blocked  # blocker と blocked が同じ会話にいる
    ).update(left_at=now)

    return Response({'message': 'ブロックしました'}, status=200)

@api_view(['POST'])
def report_user(request):
    target_id = request.data.get('target')
    reason = request.data.get('reason', '')
    if not target_id:
        return Response({'detail': 'target is required'}, status=400)
    try:
        target = UserProfile.objects.get(user_id=target_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'target user not found'}, status=404)

    Report.objects.create(target_user=target, reason=reason, read=False)
    # ユーザーの report_count を別途持っているならインクリメント等は各自の仕様で
    return Response({'message': 'ok'}, status=200)

User = get_user_model()

def _is_admin(request):
    # 例: クエリ or ヘッダで渡す仕組みにもできます
    admin_id = request.headers.get('X-Admin-Id') or request.query_params.get('admin_id') or request.data.get('admin_id')
    return admin_id == 'settee-admin'

# --- 短命トークン用の超シンプルな Bearer 認証 ---
class SimpleBearerAuthentication(BaseAuthentication):
    """
    Authorization: Bearer <token> を受け取り、Django signing で復号・検証してログイン扱いにする。
    settings.SIMPLE_TOKEN_SALT / SIMPLE_TOKEN_TTL_SECONDS が必要。
    """
    def authenticate(self, request):
        auth = get_authorization_header(request).split()
        if not auth:
            return None  # 認証ヘッダが無い → 他の認証に委ねる（匿名で通さない）

        if auth[0].lower() != b"bearer":
            return None

        if len(auth) == 1:
            raise AuthenticationFailed("Invalid Authorization header: no credentials provided")
        if len(auth) > 2:
            raise AuthenticationFailed("Invalid Authorization header: token string should not contain spaces")

        token = auth[1].decode("utf-8")
        try:
            payload = signing.loads(
                token,
                salt=settings.SIMPLE_TOKEN_SALT,
                max_age=getattr(settings, "SIMPLE_TOKEN_TTL_SECONDS", 900),
            )
        except signing.SignatureExpired:
            raise AuthenticationFailed("Token expired")
        except signing.BadSignature:
            raise AuthenticationFailed("Bad token signature")

        uid = payload.get("u")
        if not uid:
            raise AuthenticationFailed("Malformed token")

        try:
            user = User.objects.get(pk=uid)
        except User.DoesNotExist:
            raise AuthenticationFailed("User not found")

        return (user, None)


# --- 管理者判定のヘルパ ---
def _is_admin(request):
    user = getattr(request, "user", None)
    return bool(user and getattr(user, "is_staff", False))


# --- トークン発行（AllowAnyでOK：中で username/password を検証） ---
@api_view(["POST"])
@permission_classes([AllowAny])
def admin_issue_token(request):
    """
    body: { "username": "settee-admin", "password": "****" }
    return: { "access": "<token>", "expires_in": 900 }
    """
    username = request.data.get("username")
    password = request.data.get("password")
    user = authenticate(username=username, password=password)
    if not user or not getattr(user, "is_staff", False):
        return Response({"error": "invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)

    payload = {"u": user.pk, "iat": int(time.time())}
    token = signing.dumps(payload, salt=settings.SIMPLE_TOKEN_SALT)

    return Response(
        {"access": token, "expires_in": getattr(settings, "SIMPLE_TOKEN_TTL_SECONDS", 900)},
        status=200,
    )

# ---- ユーザーID一覧（新規登録順） ----
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_user_ids(request):
    try:
        limit = int(request.GET.get('limit', 50))
        offset = int(request.GET.get('offset', 0))
    except (TypeError, ValueError):
        return Response({'error': 'invalid limit/offset'}, status=400)

    limit = max(1, min(limit, 200))
    offset = max(0, offset)

    qs = (UserProfile.objects
          .order_by('-id')
          .values_list('user_id', flat=True)[offset:offset+limit])
    return Response(list(qs), status=200)

# ---- 画像削除（パストラバーサル対策）----
@api_view(['DELETE'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_delete_image(request, user_id, filename):
    safe = os.path.basename(filename)
    if safe != filename:
        return Response({'error': 'invalid filename'}, status=400)

    file_path = os.path.join(settings.BASE_DIR, 'images', user_id, safe)
    if not os.path.exists(file_path):
        return Response({'error': 'not found'}, status=404)

    try:
        os.remove(file_path)
        return Response({'message': 'deleted'}, status=200)
    except Exception as e:
        return Response({'error': str(e)}, status=500)

# ----　BAN 設定 ----
@api_view(['POST'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_ban_user(request):
    target_id = request.data.get('target_user_id')
    ban = bool(request.data.get('ban', True))
    try:
        user = UserProfile.objects.get(user_id=target_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'not found'}, status=404)

    # is_banned フィールドが UserProfile に必要（BooleanField(default=False) 等）
    user.is_banned = ban
    user.save(update_fields=['is_banned'])
    return Response({'message': 'ok', 'is_banned': user.is_banned}, status=200)

# @api_view(['GET'])
# @authentication_classes([SimpleBearerAuthentication])
# def admin_messages_between(request, user_a, user_b):
#     if not _is_admin(request):
#         return Response({'error': 'forbidden'}, status=403)
#     try:
#         ua = UserProfile.objects.get(user_id=user_a)
#     except UserProfile.DoesNotExist:
#         return Response({'error': 'user_a not found'}, status=404)
#     try:
#         ub = UserProfile.objects.get(user_id=user_b)
#     except UserProfile.DoesNotExist:
#         return Response({'error': 'user_b not found'}, status=404)

#     msgs = Message.objects.filter(
#         sender__in=[ua, ub], receiver__in=[ua, ub]
#     ).order_by('timestamp').select_related('sender', 'receiver')
#     ser = MessageSerializer(msgs, many=True)
#     return Response(ser.data, status=200)

@api_view(['POST'])
@authentication_classes([SimpleBearerAuthentication])
def admin_ban_user(request):
    if not _is_admin(request):
        return Response({'error': 'forbidden'}, status=403)
    target_id = request.data.get('target_user_id')
    ban = request.data.get('ban', True)
    try:
        user = UserProfile.objects.get(user_id=target_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'not found'}, status=404)
    user.is_banned = bool(ban)
    user.save(update_fields=['is_banned'])
    return Response({'message': 'ok', 'is_banned': user.is_banned}, status=200)

# チケット番号→コスト（ポイント）をサーバ側でも持っておくと安全
TICKET_COSTS = {
    1: 15,  # boost
    2: 25,  # refine
    3: 35,  # private
    4: 45,  # message_like5
    5: 55,  # super_like5
    6: 65,  # settee_plus_1day
    7: 65,  # settee_vip_1day
}

def _serialize_ticket(t: UserTicket):
    return {
        'id': t.id,
        'ticket_code': t.ticket_code,
        'status': t.status,
        'acquired_at': t.acquired_at.isoformat(),
        'expires_at': t.expires_at.isoformat() if t.expires_at else None,
    }

@api_view(['GET'])
def user_tickets(request, user_id):
    user = get_object_or_404(UserProfile, user_id=user_id)
    qs = user.tickets.order_by('-acquired_at')
    data = [_serialize_ticket(t) for t in qs]
    return JsonResponse(data, safe=False, status=200)

@api_view(['POST'])
def exchange_ticket(request, user_id):
    """
    チケット交換（ポイント消費→UserTicket発行）
    JSON: {"ticket_code": 1}
    """
    user = get_object_or_404(UserProfile, user_id=user_id)
    try:
        payload = request.data if hasattr(request, 'data') else json.loads(request.body.decode())
    except Exception:
        payload = {}

    code = int(payload.get('ticket_code', 0))
    if code not in TICKET_COSTS:
        return JsonResponse({'detail': 'invalid ticket_code'}, status=400)

    cost = TICKET_COSTS[code]
    if user.settee_points < cost:
        return JsonResponse({'detail': 'insufficient points'}, status=400)

    # ポイント減算
    user.settee_points -= cost

    # 期限の初期値（必要なものだけ設定。不要なら None）
    expires_at = None
    if code == 1:  # boost 24h
        expires_at = timezone.now() + timedelta(hours=48)  # 未使用でも自動失効させたいなら設定。不要なら None

    t = UserTicket.objects.create(
        user=user,
        ticket_code=code,
        status='unused',
        expires_at=expires_at,
        source='exchange',
    )
    user.save()

    return JsonResponse({
        'ticket': _serialize_ticket(t),
        'points_balance': user.settee_points,
    }, status=200)

@api_view(['GET'])
def get_user_entitlements(request, user_id: str):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    # ❶ ここが超重要：現在時点の枠を正しく整えて DB にも保存
    user.ensure_quotas_now(save=True)

    now = timezone.now()

    # ❷ 新仕様：モデルの集約返却をそのまま使う
    ent = user.get_entitlements()  # ← あなたのモデル内で定義済み

    # ent の例:
    # {
    #   'tier': 'VIP' | 'PLUS' | 'NORMAL',
    #   'like_unlimited': bool,
    #   'normal_like_remaining': None or int,
    #   'normal_like_reset_at': None or datetime,
    #   'super_like_credits': int,
    #   'treat_like_credits': int,
    #   'message_like_credits': int,
    #   'backtrack_enabled': bool,
    #   'boost_active': bool,
    #   'private_mode_active': bool,
    #   'settee_plus_active': bool,
    # }

    # ❸ 追加で until 系や refine など、旧レスポンス項目もフォロー（互換維持）
    def iso(dt): return dt.isoformat() if dt else None

    payload = {
        'tier': ent.get('tier'),
        'like_unlimited': ent.get('like_unlimited'),
        'normal_like_remaining': ent.get('normal_like_remaining'),
        'normal_like_reset_at': ent.get('normal_like_reset_at'),
        'super_like_credits': ent.get('super_like_credits', 0),
        'treat_like_credits': ent.get('treat_like_credits', 0),
        'message_like_credits': ent.get('message_like_credits', 0),
        'backtrack_enabled': ent.get('backtrack_enabled', False),
        'boost_active': ent.get('boost_active', False),
        'private_mode_active': ent.get('private_mode_active', False),
        'settee_plus_active': ent.get('settee_plus_active', False),

        'user_id': user.user_id,
        'settee_points': int(getattr(user, 'settee_points', 0) or 0),
        'refine_unlocked': bool(getattr(user, 'refine_unlocked', False)),
        'settee_plus_until': iso(getattr(user, 'settee_plus_until', None)),
        'settee_vip_until':  iso(getattr(user, 'settee_vip_until', None)),
        'boost_until':        iso(getattr(user, 'boost_until', None)),
        'private_mode_until': iso(getattr(user, 'private_mode_until', None)),
        'can_message_like': (ent.get('message_like_credits', 0) or 0) > 0,
        'can_super_like':   (ent.get('super_like_credits', 0) or 0) > 0,
        'settee_vip_active':  (user.settee_vip_until  and user.settee_vip_until  > now) or (ent.get('tier') == 'VIP'),
        'settee_plus_active': (user.settee_plus_until and user.settee_plus_until > now) or (ent.get('tier') == 'PLUS'),

        # ログ・同期用
        'server_time': now.isoformat(),
    }

    # 最後に datetime を ISO 文字列へ（get_entitlements が datetime を返す想定ならここで正規化）
    if isinstance(payload.get('normal_like_reset_at'), timezone.datetime.__mro__[0]):
        payload['normal_like_reset_at'] = iso(payload['normal_like_reset_at'])

    return Response(payload, status=200)

@api_view(['POST'])
def use_ticket(request, user_id, ticket_id):
    """
    チケットを使用（効果適用→status=used）
    """
    user = get_object_or_404(UserProfile, user_id=user_id)
    t = get_object_or_404(UserTicket, id=ticket_id, user=user)

    if t.status != 'unused':
        return JsonResponse({'detail': 'unusable status'}, status=400)
    if t.expires_at and t.expires_at < timezone.now():
        t.status = 'expired'
        t.save(update_fields=['status'])
        return JsonResponse({'detail': 'expired'}, status=400)

    # 効果適用（code で条件分岐）
    now = timezone.now()
    if t.ticket_code == 1:
        # BOOST: 24時間
        user.boost_until = max(user.boost_until or now, now) + timedelta(hours=24)
    elif t.ticket_code == 2:
        # REFINE: 永続開放（必要に応じ期間制に変える）
        user.refine_unlocked = True
    elif t.ticket_code == 3:
        # PRIVATE: 365日
        base = user.private_mode_until if (user.private_mode_until and user.private_mode_until > now) else now
        user.private_mode_until = base + timedelta(days=365)
    elif t.ticket_code == 4:
        # MESSAGE_LIKE_5
        user.message_like_credits = (user.message_like_credits or 0) + 5
    elif t.ticket_code == 5:
        # SUPER_LIKE_5
        user.super_like_credits = (user.super_like_credits or 0) + 5
    elif t.ticket_code == 6:
        # SETTEE_PLUS_1DAY
        base = user.settee_plus_until if (user.settee_plus_until and user.settee_plus_until > now) else now
        user.settee_plus_until = base + timedelta(days=1)
    elif t.ticket_code == 7:
        # SETTEE_VIP_1DAY
        base = user.settee_vip_until if (user.settee_vip_until and user.settee_vip_until > now) else now
        user.settee_vip_until = base + timedelta(days=1)

        # VIP有効化時のクレジット付与（各+10）
        user.super_like_credits = (user.super_like_credits or 0) + 10
        user.message_like_credits = (user.message_like_credits or 0) + 10
        user.treat_like_credits = (user.treat_like_credits or 0) + 10
    else:
        return JsonResponse({'detail': 'unknown ticket_code'}, status=400)

    # 使用確定
    t.status = 'used'
    t.used_at = now
    t.save(update_fields=['status', 'used_at'])
    user.save()

    return JsonResponse({
        'ticket': _serialize_ticket(t),
        'user': {
            'settee_points': user.settee_points,
            'boost_until': user.boost_until.isoformat() if user.boost_until else None,
            'private_mode_until': user.private_mode_until.isoformat() if user.private_mode_until else None,
            'message_like_credits': user.message_like_credits,
            'super_like_credits': user.super_like_credits,
            'settee_plus_until': user.settee_plus_until.isoformat() if user.settee_plus_until else None,
            'refine_unlocked': user.refine_unlocked,
        }
    }, status=200)

def has_settee_plus_active(user: UserProfile) -> bool:
    """
    Settee+ 有効判定（例）
    - ユーザーに settee_plus_until (DateTimeField) がある想定。
    - 未実装なら、あなたの環境に合わせて判定を書き換えてください。
    """
    until = getattr(user, 'settee_plus_until', None)
    if until is None:
        return False
    return until >= timezone.now()

@api_view(['GET'])
def liked_users(request, current_user_id: str):
    """
    current_user_id を受け取り、そのユーザーを 'receiver' とする LikeAction の sender を列挙。
    全てのユーザーがアクセス可能（フロントエンドでFREEユーザーにはモザイク表示）。
    """
    try:
        me = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    # 自分を Like した sender を新しい順に最大100件
    likes_qs = (LikeAction.objects
                .filter(receiver=me)
                .select_related('sender')
                .order_by('-created_at')[:100])

    out = []
    for la in likes_qs:
        s = la.sender
        if s is None:
            continue
        out.append({
            'user_id': s.user_id,
            'nickname': s.nickname,
        })

    return Response(out, status=200)

# --- 短命トークン用の超シンプルな Bearer 認証 ---
class SimpleBearerAuthentication(BaseAuthentication):
    """
    Authorization: Bearer <token> を受け取り、Django signing で復号・検証してログイン扱いにする。
    settings.SIMPLE_TOKEN_SALT / SIMPLE_TOKEN_TTL_SECONDS が必要。
    """
    def authenticate(self, request):
        auth = get_authorization_header(request).split()
        if not auth:
            return None  # 認証ヘッダが無い → 他の認証に委ねる（匿名で通さない）

        if auth[0].lower() != b"bearer":
            return None

        if len(auth) == 1:
            raise AuthenticationFailed("Invalid Authorization header: no credentials provided")
        if len(auth) > 2:
            raise AuthenticationFailed("Invalid Authorization header: token string should not contain spaces")

        token = auth[1].decode("utf-8")
        try:
            payload = signing.loads(
                token,
                salt=settings.SIMPLE_TOKEN_SALT,
                max_age=getattr(settings, "SIMPLE_TOKEN_TTL_SECONDS", 900),
            )
        except signing.SignatureExpired:
            raise AuthenticationFailed("Token expired")
        except signing.BadSignature:
            raise AuthenticationFailed("Bad token signature")

        uid = payload.get("u")
        if not uid:
            raise AuthenticationFailed("Malformed token")

        try:
            user = User.objects.get(pk=uid)
        except User.DoesNotExist:
            raise AuthenticationFailed("User not found")

        return (user, None)


# --- 管理者判定のヘルパ ---
def _is_admin(request):
    user = getattr(request, "user", None)
    return bool(user and getattr(user, "is_staff", False))


# --- トークン発行（AllowAnyでOK：中で username/password を検証） ---
@api_view(["POST"])
@permission_classes([AllowAny])
def admin_issue_token(request):
    """
    body: { "username": "settee-admin", "password": "****" }
    return: { "access": "<token>", "expires_in": 900 }
    """
    username = request.data.get("username")
    password = request.data.get("password")
    user = authenticate(username=username, password=password)
    if not user or not getattr(user, "is_staff", False):
        return Response({"error": "invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)

    payload = {"u": user.pk, "iat": int(time.time())}
    token = signing.dumps(payload, salt=settings.SIMPLE_TOKEN_SALT)

    return Response(
        {"access": token, "expires_in": getattr(settings, "SIMPLE_TOKEN_TTL_SECONDS", 900)},
        status=200,
    )

# ---- 2) ユーザーID一覧（新規登録順） ----
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_user_ids(request):
    try:
        limit = int(request.GET.get('limit', 50))
        offset = int(request.GET.get('offset', 0))
    except (TypeError, ValueError):
        return Response({'error': 'invalid limit/offset'}, status=400)

    limit = max(1, min(limit, 200))
    offset = max(0, offset)

    qs = (UserProfile.objects
          .order_by('-id')
          .values_list('user_id', flat=True)[offset:offset+limit])
    return Response(list(qs), status=200)

# ---- 3) あるユーザーの画像一覧 ----
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_list_images_for_user(request, user_id):
    base_dir = os.path.join(settings.BASE_DIR, 'images', user_id)
    results = []
    if os.path.isdir(base_dir):
        for fname in os.listdir(base_dir):
            # 任意で隠しファイル等を除外
            if fname.startswith('.'):
                continue
            results.append({
                'user_id': user_id,
                'filename': fname,
                'url': f'https://settee.jp/images/{user_id}/{fname}',
            })
    return Response(results, status=200)

# ---- 4) 画像削除（パストラバーサル対策）----
@api_view(['DELETE'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_delete_image(request, user_id, filename):
    safe = os.path.basename(filename)
    if safe != filename:
        return Response({'error': 'invalid filename'}, status=400)

    file_path = os.path.join(settings.BASE_DIR, 'images', user_id, safe)
    if not os.path.exists(file_path):
        return Response({'error': 'not found'}, status=404)

    try:
        os.remove(file_path)
        return Response({'message': 'deleted'}, status=200)
    except Exception as e:
        return Response({'error': str(e)}, status=500)

# ---- 5) 通報ランキング ----
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_users_by_reports(request):
    # report_count フィールドが存在する前提
    users = (UserProfile.objects
             .filter(report_count__gt=0)
             .order_by('-report_count', 'user_id'))
    data = [{'user_id': u.user_id, 'nickname': u.nickname, 'report_count': u.report_count}
            for u in users]
    return Response(data, status=200)

# ---- 6) BAN 設定 ----
@api_view(['POST'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_ban_user(request):
    target_id = request.data.get('target_user_id')
    ban = bool(request.data.get('ban', True))
    try:
        user = UserProfile.objects.get(user_id=target_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'not found'}, status=404)

    # is_banned フィールドが UserProfile に必要（BooleanField(default=False) 等）
    user.is_banned = ban
    user.save(update_fields=['is_banned'])
    return Response({'message': 'ok', 'is_banned': user.is_banned}, status=200)

# @api_view(['GET'])
# @authentication_classes([SimpleBearerAuthentication])
# def admin_messages_between(request, user_a, user_b):
#     if not _is_admin(request):
#         return Response({'error': 'forbidden'}, status=403)
#     try:
#         ua = UserProfile.objects.get(user_id=user_a)
#     except UserProfile.DoesNotExist:
#         return Response({'error': 'user_a not found'}, status=404)
#     try:
#         ub = UserProfile.objects.get(user_id=user_b)
#     except UserProfile.DoesNotExist:
#         return Response({'error': 'user_b not found'}, status=404)

#     msgs = Message.objects.filter(
#         sender__in=[ua, ub], receiver__in=[ua, ub]
#     ).order_by('timestamp').select_related('sender', 'receiver')
#     ser = MessageSerializer(msgs, many=True)
#     return Response(ser.data, status=200)

@api_view(['POST'])
@authentication_classes([SimpleBearerAuthentication])
def admin_ban_user(request):
    if not _is_admin(request):
        return Response({'error': 'forbidden'}, status=403)
    target_id = request.data.get('target_user_id')
    ban = request.data.get('ban', True)
    try:
        user = UserProfile.objects.get(user_id=target_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'not found'}, status=404)
    user.is_banned = bool(ban)
    user.save(update_fields=['is_banned'])
    return Response({'message': 'ok', 'is_banned': user.is_banned}, status=200)

# 電話番号の簡易正規化・検証
PHONE_RE = re.compile(r'^\+?\d{8,15}$')  # + を含め 8〜15 桁を許容

def normalize_phone(raw: str) -> str:
    s = re.sub(r'[^\d+]', '', raw or '')
    if '+' in s[1:]:
        s = s.replace('+', '')  # 先頭以外の + は除去
    return s

@api_view(['POST'])
def change_email(request, user_id):
    """
    メールアドレス変更（POST）
    正規化なし・完全一致で user を取得（他APIと同一方針）
    POST /users/<user_id>/email/change
    body: { "email": "new@example.com" }
    """
    # ★ 正規化しない／__iexact も使わない
    user = get_object_or_404(UserProfile, user_id=user_id)

    # 受信値をそのまま扱う（strip 等もしない）
    new_email = request.data.get('email')
    if not isinstance(new_email, str) or new_email == '':
        return Response({'error': 'email は必須です'}, status=status.HTTP_400_BAD_REQUEST)

    # 形式チェック（ここは妥当性確認だけ / 変更不要ならスキップ可）
    try:
        EmailValidator()(new_email)
    except ValidationError:
        return Response({'error': 'メールアドレスの形式が不正です'}, status=status.HTTP_400_BAD_REQUEST)

    # 変更なし → 200（冪等）
    if user.email == new_email:
        return Response({
            'message': 'メールアドレスは変更されていません',
            'user_id': user.user_id,
            'email': user.email,
        }, status=status.HTTP_200_OK)

    # ユニーク衝突は DB の設定に合わせて “完全一致” で確認（__iexact は使わない）
    if UserProfile.objects.filter(email=new_email).exclude(pk=user.pk).exists():
        return Response({'error': 'このメールアドレスは既に使用されています'}, status=status.HTTP_409_CONFLICT)

    try:
        with transaction.atomic():
            user.email = new_email  # ★ 正規化しない
            user.save(update_fields=['email'])
    except IntegrityError:
        return Response({'error': 'このメールアドレスは既に使用されています'}, status=status.HTTP_409_CONFLICT)

    return Response({
        'message': 'メールアドレスを更新しました',
        'user_id': user.user_id,
        'email': user.email,
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
def change_phone(request, user_id):
    """
    電話番号変更（POST）
    POST /api/users/<user_id>/phone/change
    body: { "phone": "+819012345678" }
    """
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=status.HTTP_404_NOT_FOUND)

    raw_phone = (request.data.get('phone') or '').strip()
    if not raw_phone:
        return Response({'error': 'phone は必須です'}, status=status.HTTP_400_BAD_REQUEST)

    normalized = normalize_phone(raw_phone)
    if not PHONE_RE.match(normalized):
        return Response({'error': '電話番号の形式が不正です（+と数字のみ、8〜15桁想定）'}, status=status.HTTP_400_BAD_REQUEST)

    # 変更なし → 冪等に 200
    current_norm = normalize_phone(user.phone or '')
    if current_norm == normalized:
        return Response({
            'message': '電話番号は変更されていません',
            'user_id': user.user_id,
            'phone': user.phone,
            'verification_mode': 'disabled',
        }, status=status.HTTP_200_OK)

    # ユニーク衝突 事前確認
    if UserProfile.objects.filter(phone=normalized).exclude(pk=user.pk).exists():
        return Response({'error': 'この電話番号は既に使用されています'}, status=status.HTTP_409_CONFLICT)

    try:
        with transaction.atomic():
            user.phone = normalized
            user.save(update_fields=['phone'])
    except IntegrityError:
        return Response({'error': 'この電話番号は既に使用されています'}, status=status.HTTP_409_CONFLICT)

    return Response({
        'message': '電話番号を更新しました',
        'user_id': user.user_id,
        'phone': user.phone,
        'client_should_mark_phone_verified': False,
        'verification_mode': 'disabled',
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
def change_phone(request, user_id):
    """
    電話番号変更（POST）
    POST /api/users/<user_id>/phone/change
    body: { "phone": "+819012345678" }
    """
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=status.HTTP_404_NOT_FOUND)

    raw_phone = (request.data.get('phone') or '').strip()
    if not raw_phone:
        return Response({'error': 'phone は必須です'}, status=status.HTTP_400_BAD_REQUEST)

    normalized = normalize_phone(raw_phone)
    if not PHONE_RE.match(normalized):
        return Response({'error': '電話番号の形式が不正です（+と数字のみ、8〜15桁想定）'}, status=status.HTTP_400_BAD_REQUEST)

    # 変更なし → 冪等に 200
    current_norm = normalize_phone(user.phone or '')
    if current_norm == normalized:
        return Response({
            'message': '電話番号は変更されていません',
            'user_id': user.user_id,
            'phone': user.phone,
            'verification_mode': 'disabled',
        }, status=status.HTTP_200_OK)

    # ユニーク衝突 事前確認
    if UserProfile.objects.filter(phone=normalized).exclude(pk=user.pk).exists():
        return Response({'error': 'この電話番号は既に使用されています'}, status=status.HTTP_409_CONFLICT)

    try:
        with transaction.atomic():
            user.phone = normalized
            user.save(update_fields=['phone'])
    except IntegrityError:
        return Response({'error': 'この電話番号は既に使用されています'}, status=status.HTTP_409_CONFLICT)

    return Response({
        'message': '電話番号を更新しました（暫定：認証なし）',
        'user_id': user.user_id,
        'phone': user.phone,
        'client_should_mark_phone_verified': False,
        'verification_mode': 'disabled',
    }, status=status.HTTP_200_OK)
    
FILENAME_INDEX_RE = re.compile(r'_(\d+)(\.[A-Za-z0-9]+)?$')

def _guess_image_index(filename: str) -> int:
    m = FILENAME_INDEX_RE.search(filename)
    if not m:
        return 1
    try:
        return int(m.group(1))
    except Exception:
        return 1

@api_view(['PATCH','POST'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def toggle_reviewed(request, user_id, filename):
    """
    仕様:
    - 常にDBを更新する（mark_reviewed / mark_unreviewed は save() を必ず実行）
    - 存在しない場合でも規約ファイル名から image_index と url を復元し get_or_create で作成してから更新
    - 文字列 'true'/'false' も厳密パース
    - 同時更新を防ぐため select_for_update + transaction.atomic
    """
    # 1) 入力の正規化
    raw = request.data.get('reviewed', False)
    reviewed = raw if isinstance(raw, bool) else bool(strtobool(str(raw)))

    # 2) 当該ユーザー確認
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({"detail": "user not found"}, status=404)

    # 3) アセットをロックして取得 or 作成（常に保存可能に）
    with transaction.atomic():
        # filename を正規化（URLエンコードされたまま来てもOKにする）
        norm_filename = os.path.basename(filename)

        # get_or_create で確実に対象レコードを用意
        defaults = {
            "url": f"/images/{user_id}/{norm_filename}",
            "image_index": _guess_image_index(norm_filename),
            "reviewed": False,
            "moderation_status": "pending",
        }
        # まず読み取り
        asset = (ImageAsset.objects
                 .select_for_update()
                 .filter(user=user, filename=norm_filename)
                 .first())

        if asset is None:
            asset, _ = ImageAsset.objects.get_or_create(
                user=user, filename=norm_filename, defaults=defaults
            )

        # 4) 状態更新（必ず save() を内部で呼ぶ）
        if reviewed:
            asset.mark_reviewed(admin_user=request.user, approved=True)
        else:
            asset.mark_unreviewed()

        # 5) 返却はDBの最終値
        asset.refresh_from_db()

    return Response({
        "user_id": user_id,
        "filename": asset.filename,
        "reviewed": asset.reviewed,
        "moderation_status": asset.moderation_status,
        "image_index": asset.image_index,
    }, status=200)
    
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_list_images_for_user(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response([], status=200)

    qs = (ImageAsset.objects
          .filter(user=user)
          .values('filename', 'url', 'reviewed', 'report_count', 'moderation_status', 'image_index')
          .order_by('image_index', 'filename'))

    resp = Response(list(qs), status=200)
    resp['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    resp['Pragma'] = 'no-cache'
    return resp

# 1) 通報集計（未読数付き）：/admin/users/reports/
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_users_by_reports(request):
    """
    返却例:
    [
      { "user_id":"u123", "nickname":"Alice", "report_count": 5, "unread_count": 2 },
      ...
    ]
    """
    qs = UserProfile.objects.annotate(
        report_count=Count('reports_received', distinct=True),
        unread_count=Count('reports_received', filter=Q(reports_received__read=False), distinct=True),
    ).filter(report_count__gt=0).order_by('-unread_count', '-report_count', 'user_id')

    data = [{
        'user_id': u.user_id,
        'nickname': u.nickname,
        'report_count': u.report_count or 0,
        'unread_count': u.unread_count or 0,
    } for u in qs]

    return Response(data, status=status.HTTP_200_OK)


# 2) 対象ユーザーの通報一覧：/admin/reports/?user_id=<id>
@api_view(['GET'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_reports_list(request):
    user_id = request.query_params.get('user_id')
    if not user_id:
        return Response({'detail': 'user_id is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        target = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'target user not found'}, status=status.HTTP_404_NOT_FOUND)

    qs = Report.objects.filter(target_user=target).order_by('-created_at', '-id')
    ser = ReportSerializer(qs, many=True)
    return Response(ser.data, status=status.HTTP_200_OK)


# 3) 既読トグル（既読/未読のセット）：/admin/reports/<report_id>/read/  (PATCH/POST)
@api_view(['PATCH', 'POST'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_report_mark_read(request, report_id: int):
    try:
        r = Report.objects.get(pk=report_id)
    except Report.DoesNotExist:
        return Response({'detail': 'report not found'}, status=status.HTTP_404_NOT_FOUND)

    read = request.data.get('read', True)
    r.read = bool(read)
    r.save(update_fields=['read'])
    return Response({'id': r.id, 'read': r.read}, status=status.HTTP_200_OK)


# 4) 一括既読：/admin/users/<user_id>/reports/read_all/  (POST)
@api_view(['POST'])
@authentication_classes([SimpleBearerAuthentication])
@permission_classes([IsAdminUser])
def admin_user_reports_read_all(request, user_id: str):
    try:
        target = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'target user not found'}, status=status.HTTP_404_NOT_FOUND)

    updated = Report.objects.filter(target_user=target, read=False).update(read=True)
    return Response({'updated': updated}, status=status.HTTP_200_OK)

@api_view(['POST'])
@parser_classes([MultiPartParser, FormParser])
def upload_admin_user_image(request):
    """
    Flutterから送られた画像を /images/admin/<user_id>/ に保存し、
    ImageAsset を upsert（差し替え時はレビュー状態を pending に戻す）します。

    保存ファイル:
      /images/admin/<user_id>/<user_id>_<image_index>.<ext>
    例:
      /images/admin/u123/u123_1.jpg

    フォーム項目:
      - user_id (必須)
      - image (必須): ファイル
      - image_index (任意, default=1): 1以上の整数
    """
    print("upload_admin_user_image is called")

    user_id = request.data.get("user_id")
    image_file = request.FILES.get("image")
    image_index_raw = request.data.get("image_index", "1")

    if not user_id or not image_file:
        return Response({"detail": "user_id と image を含めてください"}, status=400)

    try:
        image_index = int(image_index_raw)
        if image_index < 1:
            raise ValueError
    except Exception:
        return Response({"detail": "image_index は 1 以上の整数で指定してください"}, status=400)

    # ユーザー存在確認
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({"detail": "指定されたユーザーが存在しません"}, status=404)

    # 保存先: BASE_DIR/images/admin/<user_id>/
    base_images_dir = os.path.join(settings.BASE_DIR, 'images')
    upload_dir = os.path.join(base_images_dir, 'admin', user_id)
    os.makedirs(upload_dir, exist_ok=True)

    # 拡張子（なければ .jpg）
    ext = os.path.splitext(image_file.name)[1] or ".jpg"
    new_filename = f"{user_id}_{image_index}{ext.lower()}"
    file_path = os.path.join(upload_dir, new_filename)

    # 物理保存
    try:
        with open(file_path, 'wb+') as destination:
            for chunk in image_file.chunks():
                destination.write(chunk)
    except Exception as e:
        return Response({"detail": f"ファイル保存中にエラー: {str(e)}"}, status=500)

    # 相対URL（静的配信の設定に合わせる）
    rel_url = f"/images/admin/{user_id}/{new_filename}"

    # DB upsert（差し替え時は pending に戻す）
    try:
        with transaction.atomic():
            asset, created = ImageAsset.objects.select_for_update().get_or_create(
                user=user,
                image_index=image_index,
                defaults={
                    "filename": new_filename,
                    "url": rel_url,
                    "reviewed": False,
                    "moderation_status": "pending",
                    "report_count": 0,
                }
            )
            if not created:
                asset.filename = new_filename
                asset.url = rel_url
                asset.reviewed = False
                asset.reviewed_at = None
                asset.reviewed_by = None
                asset.moderation_status = "pending"
                asset.save(update_fields=[
                    "filename", "url", "reviewed", "reviewed_at", "reviewed_by", "moderation_status"
                ])
    except Exception as e:
        return Response({"detail": f"DB更新中にエラー: {str(e)}"}, status=500)

    return Response({
        "message": "画像のアップロードに成功しました",
        "path": rel_url,
        "image_index": image_index,
        "reviewed": False,
        "moderation_status": "pending"
    }, status=200)
    
# --- KYC 画像のベースディレクトリ: <MEDIA_ROOT>/admin/<user_id>/ ---
def _kyc_user_dir(user_id: str) -> str:
    return os.path.join(settings.MEDIA_ROOT, 'admin', user_id)

def _safe_path(base: str, *parts: str) -> str:
    """パストラバーサル防止"""
    p = os.path.normpath(os.path.join(base, *parts))
    if not p.startswith(os.path.normpath(base) + os.sep):
        raise Http404("invalid path")
    return p

def _is_img(name: str) -> bool:
    name = name.lower()
    return name.endswith(('.jpg', '.jpeg', '.png', '.webp', '.gif'))

def _reviewed_meta_path(user_id: str) -> str:
    return os.path.join(_kyc_user_dir(user_id), '.reviewed.json')

def _load_reviewed_map(user_id: str) -> dict:
    path = _reviewed_meta_path(user_id)
    if os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                m = json.load(f)
                return m if isinstance(m, dict) else {}
        except Exception:
            return {}
    return {}

def _save_reviewed_map(user_id: str, m: dict) -> None:
    path = _reviewed_meta_path(user_id)
    try:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(m, f, ensure_ascii=False, indent=2)
    except Exception:
        pass
    
def _public_user_dir(user_id: str) -> str:
    # /images/<user_id>
    return os.path.join(settings.MEDIA_ROOT, user_id)

def _safe_rmtree(path: str) -> bool:
    """
    MEDIA_ROOT 配下の指定ディレクトリのみを安全に削除。
    失敗しても例外は外に飛ばさず False を返す。
    """
    try:
        media_root = os.path.realpath(settings.MEDIA_ROOT)
        target = os.path.realpath(path)
        # ルート外やルートと同一ディレクトリを誤って消さないための安全弁
        if not target.startswith(media_root + os.sep):
            return False
        if not os.path.isdir(target):
            return False
        shutil.rmtree(target, ignore_errors=True)
        return True
    except Exception:
        return False

# ------------- KYC: 画像配信（serve_imageの踏襲／パスだけ変更） -------------
@api_view(['GET'])
def serve_kyc_image(request, user_id: str, filename: str):
    """
    /images/admin/<user_id>/<filename>
    MEDIA_ROOT/admin/<user_id>/<filename> をそのまま返す
    """
    base = _kyc_user_dir(user_id)
    image_path = _safe_path(base, filename)
    if not os.path.exists(image_path):
        raise Http404("画像が存在しません")

    ctype, _ = mimetypes.guess_type(image_path)
    return FileResponse(open(image_path, 'rb'), content_type=ctype or 'application/octet-stream')

# ------------- KYC: 一覧（DBを使わずFSを直接読む） -------------
@api_view(['GET'])
def admin_kyc_list_images_for_user(request, user_id: str):
    """
    /admin/kyc/images/<user_id>/
    → <MEDIA_ROOT>/admin/<user_id>/ を走査して JSON で返す
    ユーザディレクトリ未作成でも 200 [] を返す。
    """
    base = _kyc_user_dir(user_id)
    if not os.path.isdir(base):
        return Response([], status=200)

    reviewed_map = _load_reviewed_map(user_id)

    files = []
    for name in sorted(os.listdir(base)):
        if not _is_img(name):
            continue
        url = f"{settings.MEDIA_URL.rstrip('/')}/admin/{user_id}/{name}"  # 例: /images/admin/u123/xxx.jpg
        files.append({
            "filename": name,
            "url": url,
            "image_index": None,          # 必要なら命名規則から抽出してください
            "reviewed": bool(reviewed_map.get(name, False)),
            "moderation_status": "pending",
            "report_count": 0,
        })
    return Response(files, status=200)

# ------------- KYC: 画像削除（FS削除 + reviewedメタ更新） -------------
@api_view(['DELETE'])
def admin_kyc_delete_image(request, user_id: str, filename: str):
    """
    /admin/kyc/images/<user_id>/<filename>
    """
    base = _kyc_user_dir(user_id)
    path = _safe_path(base, filename)
    if not os.path.exists(path):
        raise Http404("画像が存在しません")
    os.remove(path)

    m = _load_reviewed_map(user_id)
    if filename in m:
        del m[filename]
        _save_reviewed_map(user_id, m)

    return Response({"ok": True}, status=200)

# ------------- KYC: reviewed トグル（DB代わりにJSONに保持） -------------
@api_view(['POST', 'PATCH'])
def admin_kyc_toggle_reviewed(request, user_id: str, filename: str):
    """
    /admin/kyc/images/<user_id>/<filename>/reviewed/
    body: {"reviewed": true/false}
    """
    # ファイルの存在だけ確認
    base = _kyc_user_dir(user_id)
    path = _safe_path(base, filename)
    if not os.path.exists(path):
        raise Http404("画像が存在しません")

    reviewed = bool(request.data.get('reviewed'))
    m = _load_reviewed_map(user_id)
    m[filename] = reviewed
    _save_reviewed_map(user_id, m)
    return Response({"filename": filename, "reviewed": reviewed}, status=200)

# ------------- KYC: 管理者によるアカウント削除 -------------
@api_view(['POST'])
def admin_kyc_delete_user(request, user_id: str):
    """
    /admin/kyc/users/<user_id>/delete/
    - ユーザー本体を削除
    - 画像メタ（あれば）削除
    - /images/admin/<user_id> と /images/<user_id> の両方を削除
    """
    # （必要なら他の admin エンドポイント同様に Bearer チェックをここで実施）

    # ユーザー取得（いなくてもディレクトリ掃除は実行）
    user = None
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        pass

    # 画像メタの掃除（存在する場合）
    if user and ImageAsset is not None:
        try:
            ImageAsset.objects.filter(user=user, url__startswith=f"/images/admin/{user_id}/").delete()
            ImageAsset.objects.filter(user=user, url__startswith=f"/images/{user_id}/").delete()
        except Exception:
            # メタ削除失敗は致命ではないため握りつぶす
            pass

    # ユーザー本体を削除（既存の delete_account と整合が必要なら、そちらの内部ロジックを呼ぶ構成にしてOK）
    if user:
        try:
            user.delete()
        except Exception:
            # 既に関連が消えている/外部制約などで失敗するケースはあり得るため致命にしない
            pass

    # 物理ファイル削除（KYC と通常投稿の両方）
    kyc_dir = _kyc_user_dir(user_id)
    public_dir = _public_user_dir(user_id)
    kyc_deleted = _safe_rmtree(kyc_dir)
    public_deleted = _safe_rmtree(public_dir)

    return Response(
        {"ok": True, "deleted_dirs": {"kyc": kyc_deleted, "public": public_deleted}},
        status=200
    )
    
# ===== App Store レシート検証 & 権限更新 =====
UTC = ZoneInfo("UTC")

PLUS_PREFIX = 'jp.settee.app.plus.'
VIP_PREFIX  = 'jp.settee.app.vip.'

APPLE_VERIFY_PROD = getattr(settings, 'APPSTORE_RECEIPT_PRODUCTION_URL',
                            'https://buy.itunes.apple.com/verifyReceipt')
APPLE_VERIFY_SBX  = getattr(settings, 'APPSTORE_RECEIPT_SANDBOX_URL',
                            'https://sandbox.itunes.apple.com/verifyReceipt')

def _to_aware_utc_from_ms(ms: str | int | None):
    """ミリ秒 Epoch -> aware UTC datetime"""
    if not ms:
        return None
    try:
        ms_int = int(ms)
        dt = datetime.utcfromtimestamp(ms_int / 1000.0).replace(tzinfo=UTC)
        return dt
    except Exception:
        return None

def _apple_verify_receipt(receipt_b64: str, *, force_sandbox: bool | None = None) -> dict:
    """Legacy verifyReceipt（本番→21007ならSBX，再試行）。"""
    if not settings.APPSTORE_SHARED_SECRET:
        return {'status': -1, 'error': 'APPSTORE_SHARED_SECRET is not configured'}

    payload = {
        "receipt-data": receipt_b64,
        "password": settings.APPSTORE_SHARED_SECRET,
        "exclude-old-transactions": True,
    }

    def _post(url):
        try:
            resp = requests.post(url, json=payload, timeout=10)
            return resp.json()
        except Exception as e:
            logger.exception("verifyReceipt network error")
            return {'status': -1, 'error': f'network_error: {e}'}

    if not force_sandbox:
        j = _post(APPLE_VERIFY_PROD)
        if j and j.get('status') == 21007:
            j = _post(APPLE_VERIFY_SBX)
        return j or {'status': -1, 'error': 'empty response from Apple'}

    j = _post(APPLE_VERIFY_SBX)
    if j and j.get('status') == 21008:
        j = _post(APPLE_VERIFY_PROD)
    return j or {'status': -1, 'error': 'empty response from Apple'}

def _effective_expiry(item: dict):
    """1行のトランザクションから有効期限を決定。"""
    if item.get('cancellation_date_ms'):
        return None
    exp = _to_aware_utc_from_ms(item.get('expires_date_ms'))
    if not exp:
        return None
    grace = _to_aware_utc_from_ms(item.get('grace_period_expires_date_ms'))
    if grace and grace > exp:
        return grace
    return exp

def _serialize_entitlements_payload(user: UserProfile) -> dict:
    now = timezone.now()
    ent = user.get_entitlements()
    def iso(dt): return dt.isoformat() if dt else None
    payload = {
        'tier': ent.get('tier'),
        'like_unlimited': ent.get('like_unlimited'),
        'normal_like_remaining': ent.get('normal_like_remaining'),
        'normal_like_reset_at': ent.get('normal_like_reset_at'),
        'super_like_credits': ent.get('super_like_credits', 0),
        'treat_like_credits': ent.get('treat_like_credits', 0),
        'message_like_credits': ent.get('message_like_credits', 0),
        'backtrack_enabled': ent.get('backtrack_enabled', False),
        'boost_active': ent.get('boost_active', False),
        'private_mode_active': ent.get('private_mode_active', False),
        'settee_plus_active': ent.get('settee_plus_active', False),

        'user_id': user.user_id,
        'settee_points': int(getattr(user, 'settee_points', 0) or 0),
        'refine_unlocked': bool(getattr(user, 'refine_unlocked', False)),
        'settee_plus_until': iso(getattr(user, 'settee_plus_until', None)),
        'settee_vip_until':  iso(getattr(user, 'settee_vip_until', None)),
        'boost_until':        iso(getattr(user, 'boost_until', None)),
        'private_mode_until': iso(getattr(user, 'private_mode_until', None)),
        'can_message_like': (ent.get('message_like_credits', 0) or 0) > 0,
        'can_super_like':   (ent.get('super_like_credits', 0) or 0) > 0,
        'settee_vip_active':  (user.settee_vip_until  and user.settee_vip_until  > now) or (ent.get('tier') == 'VIP'),
        'settee_plus_active': (user.settee_plus_until and user.settee_plus_until > now) or (ent.get('tier') == 'PLUS'),
        'server_time': now.isoformat(),
    }
    if isinstance(payload.get('normal_like_reset_at'), timezone.datetime.__mro__[0]):
        payload['normal_like_reset_at'] = (payload['normal_like_reset_at'].isoformat()
                                           if payload['normal_like_reset_at'] else None)
    return payload

def _update_user_entitlements_by_product(
    user: UserProfile,
    product_id: str,
    expires_at,  # aware datetime or None
    *,
    allow_downgrade: bool = False,
    save_now: bool = True,
):
    """product_id に応じて Plus/VIP の期限を書き換え。"""
    field = None
    if product_id.startswith(PLUS_PREFIX):
        field = 'settee_plus_until'
    elif product_id.startswith(VIP_PREFIX):
        field = 'settee_vip_until'
    else:
        return []

    current = getattr(user, field, None)
    changed = False

    if expires_at is None:
        if allow_downgrade and current is not None:
            setattr(user, field, None)
            changed = True
    else:
        if current is None or expires_at > current or allow_downgrade:
            setattr(user, field, expires_at)
            changed = True

    if changed and save_now:
        user.save(update_fields=[field])

    return [field] if changed else []

def _apply_entitlements_from_apple_receipt(user: UserProfile, apple_json: dict) -> dict:
    """verifyReceipt 結果 → Plus/VIP 期限を更新 → 最新エンタイトルメントを返す。"""
    status = int(apple_json.get('status', -1))
    if status != 0 and status != 21006:
        return {'ok': False, 'status': status, 'apple': apple_json}

    latest = apple_json.get('latest_receipt_info') or []
    if not latest:
        receipt = apple_json.get('receipt') or {}
        latest = receipt.get('in_app') or []

    changed_fields = []
    for item in latest:
        pid = item.get('product_id') or ''
        eff = _effective_expiry(item)
        allow_down = bool(item.get('cancellation_date_ms'))
        changed_fields += _update_user_entitlements_by_product(
            user, pid, eff, allow_downgrade=allow_down, save_now=False
        )

    if changed_fields:
        user.save(update_fields=list(set(changed_fields)))

    user.ensure_quotas_now(save=True)
    return {'ok': True, 'status': 0, 'entitlements': _serialize_entitlements_payload(user)}

# ======== JWS ユーティリティ（x5c署名検証） ========

def _b64url_decode(data: str) -> bytes:
    s = data + "=" * ((4 - len(data) % 4) % 4)
    return base64.urlsafe_b64decode(s.encode('utf-8'))

def _load_cert_any(path: str):
    if not path:
        return None
    try:
        data = open(path, 'rb').read()
        try:
            return x509.load_pem_x509_certificate(data, default_backend())
        except ValueError:
            return x509.load_der_x509_certificate(data, default_backend())
    except Exception:
        logger.exception("Failed to load certificate: %s", path)
        return None

def _load_roots_from_settings():
    """Apple Root/中間を settings から読み込む（複数対応）。無ければ標準場所を使う。"""
    roots = []
    paths = []

    pems = getattr(settings, 'APPSTORE_JWS_ROOT_PEMS', None)
    if pems:
        paths.extend(pems)
    single = getattr(settings, 'APPSTORE_JWS_ROOT_PEM', None)
    if single:
        paths.append(single)

    if not paths:
        paths = [
            '/etc/ssl/apple/AppleRootCA-G3.pem',
            '/etc/ssl/apple/AppleWWDRCAG4.pem',
        ]

    for p in paths:
        c = _load_cert_any(str(p))
        if c:
            roots.append(c)
    return roots

def _verify_chain_x5c(leaf: x509.Certificate, chain: list[x509.Certificate], root_candidates: list[x509.Certificate]) -> bool:
    """
    簡易チェーン検証：署名・NotBefore/After・issuer/subject の連鎖。
    """
    now = timezone.now()
    certs = [leaf] + (chain or [])

    # 期限チェック
    for c in certs:
        nbf = c.not_valid_before
        naf = c.not_valid_after
        if nbf.tzinfo is None:
            nbf = nbf.replace(tzinfo=UTC)
        if naf.tzinfo is None:
            naf = naf.replace(tzinfo=UTC)
        if nbf > now or naf < now:
            logger.warning("x5c time window invalid: subj=%s nbf=%s naf=%s now=%s",
                           c.subject.rfc4514_string(), nbf, naf, now)
            return False

    # 連鎖署名検証
    for i in range(len(certs) - 1):
        child = certs[i]
        parent = certs[i+1]
        if child.issuer != parent.subject:
            logger.warning("x5c chain mismatch: child.issuer=%s parent.subject=%s",
                           child.issuer.rfc4514_string(), parent.subject.rfc4514_string())
            return False
        pub = parent.public_key()
        try:
            hash_alg = getattr(child, "signature_hash_algorithm", None) or hashes.SHA256()
            if isinstance(pub, ec.EllipticCurvePublicKey):
                pub.verify(child.signature, child.tbs_certificate_bytes, ec.ECDSA(hash_alg))
            else:
                pub.verify(child.signature, child.tbs_certificate_bytes, asy_padding.PKCS1v15(), hash_alg)
        except Exception:
            logger.exception("x5c parent verify failed: child=%s parent=%s",
                             child.subject.rfc4514_string(), parent.subject.rfc4514_string())
            return False

    # 末尾を Root でアンカー
    last = certs[-1]
    for root in root_candidates:
        if not root:
            continue
        try:
            if last.issuer == root.subject:
                rpub = root.public_key()
                if isinstance(rpub, ec.EllipticCurvePublicKey):
                    rpub.verify(last.signature, last.tbs_certificate_bytes, ec.ECDSA(hashes.SHA256()))
                else:
                    rpub.verify(last.signature, last.tbs_certificate_bytes, asy_padding.PKCS1v15(), hashes.SHA256())
                return True
        except Exception:
            continue

    logger.warning("x5c anchor not found. last.issuer=%s, roots=[%s]",
                   last.issuer.rfc4514_string(),
                   ", ".join(r.subject.rfc4514_string() for r in root_candidates if r))
    return False

def _jws_peek_payload(jws: str) -> dict:
    """署名検証せず payload だけ取り出す（切り分け用）。"""
    try:
        parts = jws.split('.')
        if len(parts) != 3:
            return {}
        p_b64 = parts[1]
        return json.loads(_b64url_decode(p_b64).decode('utf-8'))
    except Exception:
        return {}

def _jws_decode_verified(jws: str) -> tuple[bool, dict]:
    """
    x5c で JWS 署名を検証して payload(JSON) を返す。
    ルート PEM が未設定なら False。
    """
    roots = _load_roots_from_settings()
    if not roots:
        logger.warning("No Apple Root PEMs configured; cannot verify JWS.")
        return False, {}

    try:
        h_b64, p_b64, s_b64 = jws.split('.')
    except ValueError:
        return False, {}

    try:
        header = json.loads(_b64url_decode(h_b64).decode('utf-8'))
        payload = json.loads(_b64url_decode(p_b64).decode('utf-8'))
        sig = _b64url_decode(s_b64)
    except Exception:
        return False, {}

    x5c_list = header.get('x5c') or []
    if not x5c_list:
        logger.warning("JWS header has no x5c")
        return False, {}

    def _to_cert(b64der: str) -> x509.Certificate:
        der = base64.b64decode(b64der.encode('utf-8'))
        return x509.load_der_x509_certificate(der, default_backend())

    try:
        leaf = _to_cert(x5c_list[0])
        chain = [_to_cert(x) for x in x5c_list[1:]]
    except Exception:
        logger.exception("Failed to parse x5c certificates")
        return False, {}

    ok_chain = _verify_chain_x5c(leaf, chain, roots)
    if not ok_chain:
        try:
            logger.warning("JWS x5c chain verify FAILED. leaf=%s issuer=%s alg=%s x5c_len=%d",
                           leaf.subject.rfc4514_string(), leaf.issuer.rfc4514_string(),
                           header.get('alg'), len(x5c_list))
        except Exception:
            logger.warning("JWS x5c chain verify FAILED (logging failed)")
        return False, {}

    pub = leaf.public_key()
    signed = (h_b64 + '.' + p_b64).encode('utf-8')
    alg = (header.get('alg') or '').upper()

    try:
        if isinstance(pub, ec.EllipticCurvePublicKey) and alg == 'ES256':
            pub.verify(sig, signed, ec.ECDSA(hashes.SHA256()))
        elif isinstance(pub, rsa.RSAPublicKey) and alg in ('RS256', 'RS512'):
            pub.verify(sig, signed, asy_padding.PKCS1v15(), hashes.SHA256())
        else:
            logger.warning("Unsupported JWS alg or key type: alg=%s key=%s", alg, type(pub))
            return False, {}
    except Exception:
        logger.exception("JWS signature verify failed")
        return False, {}

    return True, payload

def _parse_nested_jws_to_dict(jws_nested: str) -> dict:
    ok, payload = _jws_decode_verified(jws_nested)
    if ok and payload:
        return payload
    try:
        h_b64, p_b64, _ = jws_nested.split('.')
        return json.loads(_b64url_decode(p_b64).decode('utf-8'))
    except Exception:
        return {}

def _pick_expiry_from_txn_or_renewal(txn: dict | None, rnw: dict | None):
    """期限の候補を txn/renewal から抽出。"""
    txn = txn or {}
    rnw = rnw or {}
    if txn.get('revocationDate') or rnw.get('revocationDate'):
        return None
    for key in ('gracePeriodExpiresDate',):
        if rnw.get(key):
            return _to_aware_utc_from_ms(rnw.get(key))
    for key in ('expiresDate',):
        if txn.get(key):
            return _to_aware_utc_from_ms(txn.get(key))
    for key in ('expiresDate', 'expirationDate'):
        if rnw.get(key):
            return _to_aware_utc_from_ms(rnw.get(key))
    return None

def _find_user_for_notification(app_account_token: str | None, original_tx_id: str | None) -> Optional['UserProfile']:
    token = (app_account_token or '').strip()
    if token:
        try:
            return UserProfile.objects.get(user_id=token)
        except UserProfile.DoesNotExist:
            pass
    try:
        from settee_app.models import AppStoreTransaction
    except Exception:
        AppStoreTransaction = None
    if original_tx_id and AppStoreTransaction:
        row = (AppStoreTransaction.objects.select_related('user')
               .filter(original_transaction_id=original_tx_id).first())
        if row:
            return row.user
    return None

@api_view(['POST'])
@permission_classes([AllowAny])
def app_store_notifications(request):
    """ASSN v2 を受信して反映。"""
    body = request.data if isinstance(request.data, dict) else {}
    sp = body.get('signedPayload')
    if not sp:
        logger.warning("ASSN: missing signedPayload")
        return Response({'ok': True, 'handled': False, 'reason': 'missing signedPayload'}, status=200)

    verified, payload = _jws_decode_verified(sp)
    if not verified:
        logger.warning("ASSN: JWS not verified (no root pem or invalid)")
        return Response({'ok': True, 'handled': False, 'reason': 'unverified'}, status=200)

    data = payload.get('data', {}) if isinstance(payload, dict) else {}
    txn = _parse_nested_jws_to_dict(data.get('signedTransactionInfo') or '')
    rnw = _parse_nested_jws_to_dict(data.get('signedRenewalInfo') or '')

    notification_type = (payload.get('notificationType') or '').upper()
    subtype           = (payload.get('subtype') or '') or None
    environment       = (data.get('environment') or '').upper()
    product_id        = txn.get('productId') or rnw.get('productId') or ''
    original_tx_id    = txn.get('originalTransactionId') or rnw.get('originalTransactionId') or ''
    app_account_token = txn.get('appAccountToken') or rnw.get('appAccountToken')

    revoke_like = notification_type in ('REFUND', 'REVOKE')
    exp = _pick_expiry_from_txn_or_renewal(txn, rnw)
    if revoke_like:
        exp = None

    user = _find_user_for_notification(app_account_token, original_tx_id)

    handled = False
    changed_fields = []
    ent_payload = None

    if user and product_id:
        try:
            with transaction.atomic():
                try:
                    from settee_app.models import AppStoreTransaction
                except Exception:
                    AppStoreTransaction = None
                if original_tx_id and AppStoreTransaction:
                    AppStoreTransaction.objects.update_or_create(
                        original_transaction_id=original_tx_id,
                        defaults={
                            'user': user,
                            'product_id': product_id or '',
                            'environment': (environment or '').title(),
                            'revoked': (exp is None),
                        }
                    )
                changed_fields = _update_user_entitlements_by_product(
                    user, product_id, exp,
                    allow_downgrade=revoke_like or notification_type in ('EXPIRED', 'GRACE_PERIOD_EXPIRED'),
                    save_now=True
                )
                user.ensure_quotas_now(save=True)
                ent_payload = _serialize_entitlements_payload(user)
                handled = True
        except Exception as e:
            logger.exception("ASSN: failed to update entitlements: %s", e)

    return Response({
        'ok': True,
        'handled': handled,
        'user_id': getattr(user, 'user_id', None),
        'product_id': product_id or None,
        'changed': changed_fields,
        'notificationType': notification_type,
        'subtype': subtype,
        'environment': environment,
        'entitlements': ent_payload,
    }, status=200)
    
def _jws_peek_header(jws: str) -> dict:
    try:
        h_b64 = jws.split('.')[0]
        return json.loads(_b64url_decode(h_b64).decode('utf-8'))
    except Exception:
        return {}


# ======== JWS/PKCS#7 自動判別ヘルパ ========

def _parse_bool(v):
    if isinstance(v, bool): return v
    if isinstance(v, str): return v.strip().lower() in ("1","true","t","yes","y","on")
    return False

_B64_STD_RE  = re.compile(r'^[A-Za-z0-9+/=]+$')
_B64_URL_RE  = re.compile(r'^[A-Za-z0-9\-_]+$')

def _is_probably_jws(s: str) -> bool:
    return isinstance(s, str) and s.count('.') == 2 and s.startswith('eyJ')

def coerce_base64(s: str, *, allow_urlsafe: bool = True, max_len: int = 200_000) -> str:
    """verifyReceipt に送る PKCS#7 Base64 を正規化＆厳格検証。"""
    if not isinstance(s, str):
        raise ValueError("receipt_data must be string")
    if _is_probably_jws(s):
        raise ValueError("looks like JWS, not PKCS7")
    if '%' in s:
        try:
            s = unquote(s)
        except Exception:
            pass
    s = "".join(s.split())
    if len(s) > max_len:
        raise ValueError("receipt_data too long")
    if allow_urlsafe and _B64_URL_RE.fullmatch(s) and ('-' in s or '_' in s):
        s = s.replace('-', '+').replace('_', '/')
    pad = (4 - len(s) % 4) % 4
    if pad:
        s += '=' * pad
    base64.b64decode(s, validate=True)
    return s

# ======== iOS クライアント検証（JWS/PKCS#7 両対応，Sandbox フォールバック可） ========

@api_view(['POST'])
@permission_classes([AllowAny])
def ios_verify_receipt(request):
    user_id = request.data.get('user_id')
    receipt = request.data.get('receipt_data')
    force_sandbox = request.data.get('force_sandbox', None)
    force_sandbox = _parse_bool(force_sandbox) if force_sandbox is not None else None

    if not user_id or not receipt:
        return Response({'detail': 'user_id と receipt_data は必須です'}, status=400)

    # ユーザー
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'ユーザーが存在しません'}, status=404)
    if getattr(user, 'is_banned', False):
        return Response({'detail': 'アカウントが停止されています'}, status=403)

    # --- JWS / PKCS#7 自動判別 ---
    if _is_probably_jws(receipt):
        # StoreKit 2 (JWS)
        verified, txn = _jws_decode_verified(receipt)

        if not verified:
            # 追加デバッグ情報を作る
            hdr  = _jws_peek_header(receipt)
            peek = _jws_peek_payload(receipt)
            x5c  = hdr.get('x5c') or []
            debug_info = {
                'alg': hdr.get('alg'),
                'x5c_len': len(x5c),
                'bundleId': peek.get('bundleId'),
                'productId': peek.get('productId'),
                'originalTransactionId': peek.get('originalTransactionId'),
            }
            logger.warning("JWS verify failed. alg=%s x5c_len=%s bundleId=%s productId=%s",
                           debug_info['alg'], debug_info['x5c_len'],
                           debug_info['bundleId'], debug_info['productId'])

            # ソフト受け入れ（切り分け中のみON推奨）
            soft = bool(getattr(settings, 'APPSTORE_JWS_SOFT_ACCEPT', False))
            bundle_ok = (peek.get('bundleId') == getattr(settings, 'APPSTORE_BUNDLE_ID', None))
            pid = str(peek.get('productId') or '')
            pid_ok = pid.startswith(PLUS_PREFIX) or pid.startswith(VIP_PREFIX)

            if soft and bundle_ok and pid_ok:
                logger.warning("JWS SOFT-ACCEPT: using payload without signature verification.")
                txn = peek
            else:
                # DEBUG時は JSON で詳細を返す
                if bool(getattr(settings, 'APPSTORE_JWS_DEBUG', False)) or settings.DEBUG:
                    return Response({'ok': False, 'status': -2,
                                     'detail': 'JWS verify failed',
                                     'debug': debug_info}, status=400)
                return Response({'ok': False, 'status': -2, 'detail': 'JWS verify failed'}, status=400)

        product_id = txn.get('productId') or ''
        exp = _to_aware_utc_from_ms(txn.get('expiresDate'))  # 非サブスクは None でOK
        revoke = bool(txn.get('revocationDate'))
        if revoke:
            exp = None

        try:
            with transaction.atomic():
                changed = _update_user_entitlements_by_product(
                    user, product_id, exp,
                    allow_downgrade=revoke, save_now=True
                )
                user.ensure_quotas_now(save=True)
        except Exception:
            logger.exception("Failed to apply entitlements from JWS")
            return Response({'ok': False, 'status': -3, 'detail': 'apply failed'}, status=500)

        return Response({'ok': True, 'status': 0, 'changed': changed,
                         'entitlements': _serialize_entitlements_payload(user)}, status=200)

    # ---- 旧式（PKCS#7）: verifyReceipt ----
    try:
        receipt_b64 = coerce_base64(str(receipt))
    except Exception:
        return Response({'detail': 'receipt_data が不正な Base64 です'}, status=400)

    apple_json = _apple_verify_receipt(receipt_b64, force_sandbox=force_sandbox)
    st = int(apple_json.get('status', -1))
    if st not in (0, 21006):
        return Response({'ok': False, 'status': st, 'apple_raw': apple_json}, status=400)

    try:
        with transaction.atomic():
            result = _apply_entitlements_from_apple_receipt(user, apple_json)
    except Exception:
        logger.exception("Failed to apply entitlements from Apple receipt")
        return Response({'ok': False, 'status': -3, 'detail': 'apply failed'}, status=500)

    return Response(result, status=200)
