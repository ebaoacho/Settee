import os
import re
import json
import time
import mimetypes
import shutil
import unicodedata
# from distutils.util import strtobool
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
from django.db.models import Count, Subquery, F, Q
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
from datetime import date
from .models import UserProfile, Conversation, ConversationMember, ConversationKind, LikeAction, Message, Block, UserTicket, ImageAsset, Report, LikeType, Match
from .serializers import UserProfileSerializer, LikeActionSerializer, MessageSerializer, ReportSerializer

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

    return Response({
        'id': user.id,
        'email': user.email,
        'user_id': user.user_id,
        'nickname': user.nickname,
        'message': 'ログインに成功しました'
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
        # --- 相互Like ---
        sent_likes = LikeAction.objects.filter(
            sender__user_id=current_user_id
        ).values_list('receiver__user_id', flat=True)

        received_likes = LikeAction.objects.filter(
            receiver__user_id=current_user_id
        ).values_list('sender__user_id', flat=True)

        matched_ids = set(sent_likes).intersection(set(received_likes))

        # --- 会話の共同参加者（新ロジック）---
        conv_ids = (ConversationMember.objects
                    .filter(user__user_id=current_user_id, left_at__isnull=True)
                    .values_list('conversation_id', flat=True))

        co_member_ids = set(ConversationMember.objects
            .filter(conversation_id__in=conv_ids, left_at__isnull=True)
            .exclude(user__user_id=current_user_id)
            .values_list('user__user_id', flat=True))

        partner_ids = matched_ids.union(co_member_ids)
        partner_ids.discard(current_user_id)

        # --- 片方向ブロック（自分がブロックした相手は隠す）---
        blocked_outgoing = set(Block.objects.filter(
            blocker__user_id=current_user_id
        ).values_list('blocked__user_id', flat=True))

        visible_partner_ids = partner_ids - blocked_outgoing

        users = UserProfile.objects.filter(user_id__in=visible_partner_ids)
        result = [{'user_id': u.user_id, 'nickname': u.nickname} for u in users]
        return Response(result, status=200)

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
    return Response({
        'message': 'マッチングしました',
        'match_id': match.id,
        'matched_at': match.matched_at
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

    # ユーザ解決は例外をきちんと 404 返す
    try:
        inviter = UserProfile.objects.get(user_id=inviter_id)
        invitee = UserProfile.objects.get(user_id=invitee_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=404)

    try:
        # ★ ここからトランザクション内で select_for_update を使う
        with transaction.atomic():
            conv = Conversation.objects.select_for_update().get(id=cid)

            # Double 以外はエラー（仕様に合わせて）
            if conv.kind != ConversationKind.DOUBLE:
                return Response({'error': 'WRONG_KIND'}, status=400)

            # 招待操作権限の検証（有効メンバーのみ）
            is_member = ConversationMember.objects.filter(
                conversation=conv, user=inviter, left_at__isnull=True
            ).exists()
            if not is_member:
                return Response({'error': 'FORBIDDEN'}, status=403)

            # 既に入っていれば冪等に 200 を返す（left_at があれば復帰）
            cm, created = ConversationMember.objects.get_or_create(
                conversation=conv, user=invitee, defaults={'role': 'member'}
            )
            if not created and cm.left_at is not None:
                cm.left_at = None
                cm.save(update_fields=['left_at'])

            # 上限（4人想定）チェックは「追加後」に再カウントして超過ならエラー返す
            active_count = ConversationMember.objects.filter(
                conversation=conv, left_at__isnull=True
            ).count()
            if active_count > 4:
                return Response({'error': 'MEMBER_LIMIT_REACHED'}, status=409)

            members = list(ConversationMember.objects
                .filter(conversation=conv, left_at__isnull=True)
                .values_list('user__user_id', flat=True))

        return Response({'id': conv.id, 'kind': conv.kind, 'members': members}, status=200)

    except Conversation.DoesNotExist:
        return Response({'error': 'CONV_NOT_FOUND'}, status=404)
    except Exception as e:
        # 本番では stacktrace をログに出す（Sentry 等）
        # logger.exception('invite_to_conversation failed')
        return Response({'error': 'SERVER_ERROR'}, status=500)

# ------------- 新規: 会話一覧（ユーザ別） -------------
@api_view(['GET'])
def list_conversations_for_user(request, user_id: str):
    try:
        u = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'USER_NOT_FOUND'}, status=404)

    mems = (ConversationMember.objects
            .select_related('conversation')
            .filter(user=u, left_at__isnull=True))
    data = [{
        'id': m.conversation.id,
        'kind': m.conversation.kind,
        'title': m.conversation.title,
        'members': [mm.user.user_id for mm in m.conversation.members.select_related('user')],
        'updated_at': m.conversation.updated_at.isoformat(),
        'last_message_at': m.conversation.last_message_at.isoformat() if m.conversation.last_message_at else None,
    } for m in mems]
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
def get_user_entitlements(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    now = timezone.now()

    settee_points        = int(getattr(user, 'settee_points', 0) or 0)
    message_like_credits = int(getattr(user, 'message_like_credits', 0) or 0)
    super_like_credits   = int(getattr(user, 'super_like_credits', 0) or 0)
    treat_like_credits   = int(getattr(user, 'treat_like_credits', 0) or 0)
    refine_unlocked      = bool(getattr(user, 'refine_unlocked', False))

    boost_until        = getattr(user, 'boost_until', None)
    private_mode_until = getattr(user, 'private_mode_until', None)
    settee_plus_until  = getattr(user, 'settee_plus_until', None)
    settee_vip_until  = getattr(user, 'settee_vip_until', None)

    def iso(dt): return dt.isoformat() if dt else None

    data = {
        'user_id'            : user.user_id,
        'settee_points'      : settee_points,
        'message_like_credits': message_like_credits,
        'super_like_credits' : super_like_credits,
        'treat_like_credits' : treat_like_credits,
        'refine_unlocked'    : refine_unlocked,
        'settee_plus_until'  : iso(settee_plus_until),
        'settee_vip_until'  : iso(settee_vip_until),
        'boost_until'        : iso(boost_until),
        'private_mode_until' : iso(private_mode_until),

        # サーバ時刻で判定したブールを返す
        'can_message_like'   : message_like_credits > 0,
        'can_super_like'     : super_like_credits > 0,
        'settee_plus_active' : bool(settee_plus_until  and settee_plus_until  > now),
        'settee_vip_active'  : bool(settee_vip_until   and settee_vip_until   > now),
        'boost_active'       : bool(boost_until        and boost_until        > now),
        'private_mode_active': bool(private_mode_until and private_mode_until > now),
        'can_refine'         : refine_unlocked,

        # 参照用にサーバ時刻も返す（ログ/表示用）
        'server_time'        : now.isoformat(),
    }
    return Response(data, status=200)

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
    Settee+がアクティブでなければ 403。
    """
    try:
        me = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    # サーバ側でも Settee+ を必ず検査（クライアントのみの検査は不可）
    if not has_settee_plus_active(me):
        return Response({'error': 'この機能には Settee+ が必要です'}, status=403)

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