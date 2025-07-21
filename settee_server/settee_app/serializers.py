from rest_framework import serializers
from .models import UserProfile, LikeAction, Message
from django.contrib.auth.hashers import make_password

class UserProfileSerializer(serializers.ModelSerializer):
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
        ]
        extra_kwargs = {
            'password': {'write_only': True, 'required': False, 'allow_blank': True},
            'match_multiple': {'read_only': True},
            'occupation': {'required': False, 'allow_null': True, 'allow_blank': True},
            'university': {'required': False, 'allow_null': True, 'allow_blank': True},
            'blood_type': {'required': False, 'allow_null': True, 'allow_blank': True},
            'height': {'required': False, 'allow_null': True, 'allow_blank': True},
            'drinking': {'required': False, 'allow_null': True, 'allow_blank': True},
            'smoking': {'required': False, 'allow_null': True, 'allow_blank': True},
        }

    def update(self, instance, validated_data):
        password = validated_data.pop('password', None)
        if password:  # 空文字やNoneを無視
            instance.password = make_password(password)

        # すべてのフィールドを更新
        for attr, value in validated_data.items():
            setattr(instance, attr, value)

        instance.save()
        return instance

    def validate_match_count(self, value):
        if value not in ('single', 'group'):
            raise serializers.ValidationError('match_count は "single" または "group" にしてください。')
        return value

    def create(self, validated_data):
        match_str = validated_data.pop('match_count')
        match_flag = True if match_str == 'group' else False
        raw_pwd = validated_data.pop('password')
        hashed = make_password(raw_pwd)

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
        )
        user.save()
        return user


class LikeActionSerializer(serializers.ModelSerializer):
    class Meta:
        model = LikeAction
        fields = ['id', 'sender', 'receiver', 'like_type', 'created_at']
        
class MessageSerializer(serializers.ModelSerializer):
    sender = serializers.CharField(source='sender.user_id', read_only=True)
    receiver = serializers.CharField(source='receiver.user_id', read_only=True)

    class Meta:
        model = Message
        fields = ['id', 'sender', 'receiver', 'text', 'timestamp']
