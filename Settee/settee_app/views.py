import os
from django.conf import settings
from django.contrib.auth.hashers import make_password, check_password
from django.shortcuts import get_object_or_404
from django.db import IntegrityError
from django.db.models import Count, Q
from django.http import JsonResponse, FileResponse, Http404
from rest_framework.decorators import api_view, parser_classes
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework import status
from datetime import date
from .models import UserProfile, LikeAction, Message
from .serializers import UserProfileSerializer, LikeActionSerializer, MessageSerializer

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
    Flutterから送られた画像を /images/<user_id>/ に
    【user_id_1.拡張子】というルールで保存
    """
    print("upload_user_image is called")

    user_id = request.data.get("user_id")
    image_file = request.FILES.get("image")

    if not user_id or not image_file:
        return Response({"detail": "user_id と image を含めてください"}, status=400)

    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({"detail": "指定されたユーザーが存在しません"}, status=404)

    # 保存ディレクトリ作成
    upload_dir = os.path.join(settings.BASE_DIR, 'images', user_id)
    os.makedirs(upload_dir, exist_ok=True)

    # ファイル名を「user_id_1.拡張子」に変更
    ext = os.path.splitext(image_file.name)[1]  # 拡張子（例: .jpg）
    new_filename = f"{user_id}_1{ext}"
    file_path = os.path.join(upload_dir, new_filename)

    # ファイル保存
    with open(file_path, 'wb+') as destination:
        for chunk in image_file.chunks():
            destination.write(chunk)

    return Response({
        "message": "画像のアップロードに成功しました",
        "path": f"/images/{user_id}/{new_filename}"
    }, status=200)


upload_user_image.__name__ = 'upload_user_image'

@api_view(['GET'])
def recommended_users(request, user_id):
    try:
        current_user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'detail': 'ユーザーが存在しません'}, status=404)

    # 対象性別
    if current_user.gender == '男性':
        target_gender = '女性'
    elif current_user.gender == '女性':
        target_gender = '男性'
    else:
        return Response({'detail': '性別が不明です'}, status=400)

    offset = int(request.GET.get('offset', 0))
    limit = int(request.GET.get('limit', 10))

    # 異性かつ同じマッチタイプ（みんなで or ひとりで）のユーザーを対象とする
    queryset = UserProfile.objects.filter(
        gender=target_gender,
        match_multiple=current_user.match_multiple  # 追加：マッチタイプが同じユーザー
    ).exclude(user_id=user_id)

    matched_users = []
    for user in queryset:
        if any(station in current_user.selected_area for station in user.selected_area):
            matched_users.append(user)

    paged_users = matched_users[offset:offset + limit]

    results = []
    for user in paged_users:
        image_dir = f"/images/{user.user_id}/"
        try:
            image_file = next(iter(os.listdir(os.path.join(settings.BASE_DIR, 'images', user.user_id))))
            image_url = image_dir + image_file
        except Exception:
            image_url = ""

        results.append({
            'user_id': user.user_id,
            'nickname': user.nickname,
            'age': calculate_age(user.birth_date),
            'selected_area': user.selected_area,
            'image_url': image_url,
        })

    return Response(results)


def calculate_age(birth_date):
    from datetime import date
    today = date.today()
    return today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))

@api_view(['POST'])
def like_user(request):
    sender_user_id = request.data.get('sender')
    receiver_user_id = request.data.get('receiver')
    like_type = request.data.get('like_type')

    try:
        sender = UserProfile.objects.get(user_id=sender_user_id)
        receiver = UserProfile.objects.get(user_id=receiver_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': '指定されたユーザーが存在しません'}, status=400)

    # 既存のLikeActionがあるかチェック
    try:
        existing_like = LikeAction.objects.get(sender=sender, receiver=receiver)
        if existing_like.like_type == 0:
            # 上書き許可
            existing_like.like_type = like_type
            existing_like.save()
            return Response({'message': 'Like情報を上書きしました'}, status=200)
        else:
            return Response({'error': '既にLike済みです（上書き不可）'}, status=400)
    except LikeAction.DoesNotExist:
        # 新規作成
        LikeAction.objects.create(sender=sender, receiver=receiver, like_type=like_type)
        return Response({'message': 'Like情報を保存しました'}, status=201)

@api_view(['GET'])
def get_user_profile(request, user_id):
    try:
        user = UserProfile.objects.get(user_id=user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが存在しません'}, status=404)

    data = {
        'user_id': user.user_id,
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
    }

    return Response(data, status=200)

@api_view(['GET'])
def popular_users(request, current_user_id):
    try:
        current_user = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    # 異性のユーザーをフィルタ
    opposite_gender = '男性' if current_user.gender == '女性' else '女性'

    # LikeAction の受信数が多い順に User を集計
    users = (UserProfile.objects
             .filter(gender=opposite_gender)
             .annotate(like_count=Count('received_likes'))
             .order_by('-like_count')[:3])

    data = [{'user_id': user.user_id, 'nickname': user.nickname} for user in users]
    return Response(data)


@api_view(['GET'])
def recent_users(request, current_user_id):
    try:
        current_user = UserProfile.objects.get(user_id=current_user_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    opposite_gender = '男性' if current_user.gender == '女性' else '女性'

    # IDの降順（新しい順）に異性ユーザーを3件取得
    users = (UserProfile.objects
             .filter(gender=opposite_gender)
             .order_by('-id')[:3])

    data = [{'user_id': user.user_id, 'nickname': user.nickname} for user in users]
    return Response(data)

@api_view(['GET'])
def matched_users(request, current_user_id):
    try:
        # 自分がLikeを送ったユーザー（like_type問わず）
        sent_likes = LikeAction.objects.filter(sender__user_id=current_user_id).values_list('receiver__user_id', flat=True)

        # 自分にLikeを送ってきたユーザー（like_type問わず）
        received_likes = LikeAction.objects.filter(receiver__user_id=current_user_id).values_list('sender__user_id', flat=True)

        # 双方がlikeしている場合（＝マッチしているユーザー）
        matched_ids = set(sent_likes).intersection(set(received_likes))

        # マッチユーザーのUserProfile情報を取得
        matched_users = UserProfile.objects.filter(user_id__in=matched_ids)

        result = [
            {
                'user_id': user.user_id,
                'nickname': user.nickname,
            }
            for user in matched_users
        ]

        return Response(result, status=200)

    except Exception as e:
        return Response({'error': str(e)}, status=500)
    
@api_view(['POST'])
def send_message(request):
    sender_id = request.data.get('sender')
    receiver_id = request.data.get('receiver')
    text = request.data.get('text')

    try:
        sender = UserProfile.objects.get(user_id=sender_id)
        receiver = UserProfile.objects.get(user_id=receiver_id)
    except UserProfile.DoesNotExist:
        return Response({'error': '送信者または受信者が存在しません'}, status=400)

    message = Message(sender=sender, receiver=receiver, text=text)
    message.save()

    serializer = MessageSerializer(message)
    return Response(serializer.data, status=status.HTTP_201_CREATED)

@api_view(['GET'])
def get_messages(request, user1_id, user2_id):
    try:
        user1 = UserProfile.objects.get(user_id=user1_id)
        user2 = UserProfile.objects.get(user_id=user2_id)
    except UserProfile.DoesNotExist:
        return Response({'error': 'ユーザーが見つかりません'}, status=404)

    messages = Message.objects.filter(
        sender__in=[user1, user2],
        receiver__in=[user1, user2]
    ).order_by('timestamp')

    serializer = MessageSerializer(messages, many=True)
    return Response(serializer.data)

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