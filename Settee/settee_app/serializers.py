from django.utils import timezone
from django.db import transaction
from rest_framework import serializers
from rest_framework.exceptions import ValidationError
from .models import UserProfile, LikeAction, Message, Report, LikeType
from django.contrib.auth.hashers import make_password


class UserProfileSerializer(serializers.ModelSerializer):
    # 登録時に single / group の文字列を受け取る（match_multiple へ反映）
    match_count = serializers.CharField(write_only=True, required=False)

    class Meta:
        model = UserProfile
        fields = [
            'id',
            'phone',
            'email',
            'gender',
            'birth_date',
            'nickname',
            'user_id',
            'password',
            'selected_area',
            'match_count',
            'match_multiple',
            'occupation',
            'university',
            'blood_type',
            'height',
            'drinking',
            'smoking',
            'available_dates',
            # 追加フィールド
            'zodiac',
            'mbti',
            'seeking',
            'preference',
        ]
        extra_kwargs = {
            'password': {'write_only': True, 'required': False, 'allow_blank': True},
            'match_multiple': {'read_only': True},

            # 任意項目は null/blank 許可（ただし choices のある項目は空文字は None に変換してから保存）
            'occupation': {'required': False, 'allow_null': True, 'allow_blank': True},
            'university': {'required': False, 'allow_null': True, 'allow_blank': True},
            'blood_type': {'required': False, 'allow_null': True, 'allow_blank': True},
            'height': {'required': False, 'allow_null': True, 'allow_blank': True},
            'drinking': {'required': False, 'allow_null': True, 'allow_blank': True},
            'smoking': {'required': False, 'allow_null': True, 'allow_blank': True},

            # 新規（自由記述）
            'seeking': {'required': False, 'allow_null': True, 'allow_blank': True},
            'preference': {'required': False, 'allow_null': True, 'allow_blank': True},

            # choices あり：空文字は validate() 内で None に変換
            'zodiac': {'required': False, 'allow_null': True},
            'mbti': {'required': False, 'allow_null': True},
        }

    # 共通：空文字や"未設定"は None に正規化
    def _normalize_optional_fields(self, attrs):
        to_none_if_empty = [
            'occupation', 'university', 'blood_type', 'height',
            'drinking', 'smoking', 'seeking', 'preference',
            'zodiac', 'mbti',
        ]
        for k in to_none_if_empty:
            if k in attrs:
                v = attrs.get(k)
                if isinstance(v, str) and (v.strip() == '' or v.strip() == '未設定'):
                    attrs[k] = None
        return attrs

    def validate(self, attrs):
        attrs = super().validate(attrs)
        return self._normalize_optional_fields(attrs)

    def validate_match_count(self, value):
        if value not in ('single', 'group'):
            raise serializers.ValidationError('match_count は "single" または "group" にしてください。')
        return value

    def create(self, validated_data):
        # match_count → match_multiple へ
        match_str = validated_data.pop('match_count', None)
        match_flag = True if match_str == 'group' else False

        # パスワード必須（登録時）
        raw_pwd = validated_data.pop('password', None)
        if not raw_pwd:
            raise ValidationError({'password': '登録時は password が必須です。'})
        hashed = make_password(raw_pwd)

        # 正規化（空文字や"未設定"→None）
        validated_data = self._normalize_optional_fields(validated_data)

        user = UserProfile(
            phone=validated_data['phone'],
            email=validated_data['email'],
            gender=validated_data['gender'],
            birth_date=validated_data['birth_date'],
            nickname=validated_data['nickname'],
            user_id=validated_data['user_id'],
            password=hashed,
            selected_area=validated_data.get('selected_area', []),
            match_multiple=match_flag,
            occupation=validated_data.get('occupation'),
            university=validated_data.get('university'),
            blood_type=validated_data.get('blood_type'),
            height=validated_data.get('height'),
            drinking=validated_data.get('drinking'),
            smoking=validated_data.get('smoking'),
            available_dates=validated_data.get('available_dates', []),
            # 追加フィールド
            zodiac=validated_data.get('zodiac'),
            mbti=validated_data.get('mbti'),
            seeking=validated_data.get('seeking'),
            preference=validated_data.get('preference'),
        )
        user.save()
        return user

    def update(self, instance, validated_data):
        # match_count → match_multiple（更新でも受け付ける）
        match_str = validated_data.pop('match_count', None)
        if match_str in ('single', 'group'):
            instance.match_multiple = (match_str == 'group')

        # パスワードは個別処理
        password = validated_data.pop('password', None)
        if password:  # 空文字や None は無視
            instance.password = make_password(password)

        # 正規化（空文字や"未設定"→None）
        validated_data = self._normalize_optional_fields(validated_data)

        # 残りを一括反映
        for attr, value in validated_data.items():
            setattr(instance, attr, value)

        instance.save()
        return instance


class LikeActionSerializer(serializers.ModelSerializer):
    # フロントは user_id を送ってくるため、user_id で解決
    sender = serializers.SlugRelatedField(
        slug_field='user_id', queryset=UserProfile.objects.all()
    )
    receiver = serializers.SlugRelatedField(
        slug_field='user_id', queryset=UserProfile.objects.all()
    )
    like_type = serializers.ChoiceField(choices=LikeType.choices)
    # メッセージLike以外では空OK
    message = serializers.CharField(
        allow_blank=True, allow_null=True, required=False, max_length=1000
    )

    class Meta:
        model = LikeAction
        fields = (
            'id',
            'sender', 'receiver', 'like_type',
            'message', 'message_sent_at',
            'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'message_sent_at', 'created_at', 'updated_at')

    def validate(self, attrs):
        sender = attrs.get('sender') or getattr(self.instance, 'sender', None)
        receiver = attrs.get('receiver') or getattr(self.instance, 'receiver', None)
        like_type = attrs.get('like_type') if 'like_type' in attrs else getattr(self.instance, 'like_type', LikeType.NORMAL)
        message = attrs.get('message') if 'message' in attrs else getattr(self.instance, 'message', None)

        if sender and receiver and sender == receiver:
            raise serializers.ValidationError('自分自身には送信できません。')

        # メッセージLikeは message 必須
        if int(like_type) == LikeType.MESSAGE and not (message and message.strip()):
            raise serializers.ValidationError({'message': 'メッセージLikeでは message は必須です。'})

        return attrs

    @transaction.atomic
    def create(self, validated_data):
        """
        unique_together(sender, receiver) を保ちつつ:
        - 既存行が「通常Like」の場合のみ、受信した like_type で上書き（MESSAGE なら本文/時刻も設定）
        - 既存行が「通常以外」の場合は一切上書きしない（そのまま返す）
        - 行が無ければ新規作成
        """
        sender   = validated_data['sender']
        receiver = validated_data['receiver']
        like_t   = int(validated_data['like_type'])
        message  = validated_data.get('message')

        # 同一ペアをロックして競合回避
        obj, created = LikeAction.objects.select_for_update().get_or_create(
            sender=sender, receiver=receiver,
            defaults={'like_type': like_t, 'message': message}
        )

        if created:
            # 新規作成時：MESSAGEなら送信時刻をセット
            if like_t == LikeType.MESSAGE:
                obj.message_sent_at = timezone.now()
                # updated_at がある前提なら含める
                obj.save(update_fields=['message_sent_at'])
            return obj

        # ── 既存あり ──
        if obj.like_type == LikeType.NORMAL:
            # 既存が通常Likeのときだけ上書きOK
            if like_t == LikeType.MESSAGE:
                obj.like_type = LikeType.MESSAGE
                obj.message = message
                obj.message_sent_at = timezone.now()
                obj.save(update_fields=['like_type', 'message', 'message_sent_at'])
            else:
                # 通常→（通常/スーパー/ごちそう 等）に変更
                obj.like_type = like_t
                # 非MESSAGEでは message は触らない
                obj.save(update_fields=['like_type'])
            return obj

        # 既存が通常以外（MESSAGE/スーパー/ごちそう 等）の場合は **上書きしない**
        # そのまま返却
        return obj

    @transaction.atomic
    def update(self, instance, validated_data):
        """
        PATCH/PUT 用:
        - 既存が通常Likeのときだけ更新を反映
        - 既存が通常以外なら何も変更しないで返す
        """
        if instance.like_type != LikeType.NORMAL:
            # ポリシーに従い上書き禁止
            return instance

        like_t  = int(validated_data.get('like_type', instance.like_type))
        message = validated_data.get('message', instance.message)

        if like_t == LikeType.MESSAGE:
            # 通常→メッセージ
            instance.like_type = LikeType.MESSAGE
            instance.message = message
            # 本文が来た/初回なら送信時刻
            if 'message' in validated_data or instance.message_sent_at is None:
                instance.message_sent_at = timezone.now()
            instance.save(update_fields=['like_type', 'message', 'message_sent_at'])
        else:
            # 通常→（通常/スーパー/ごちそう 等）
            instance.like_type = like_t
            instance.save(update_fields=['like_type'])

        return instance

class MessageSerializer(serializers.ModelSerializer):
    # 表示は user_id、内部は PK を使う場合は別途 write_only の sender_id/receiver_id を用意
    sender = serializers.CharField(source='sender.user_id', read_only=True)
    receiver = serializers.CharField(source='receiver.user_id', read_only=True)

    class Meta:
        model = Message
        fields = ['id', 'sender', 'receiver', 'text', 'timestamp']

class ReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = Report
        fields = ['id', 'reason', 'read', 'created_at']
