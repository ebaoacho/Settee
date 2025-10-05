from django.conf import settings
from django.core import signing
from django.contrib.auth import get_user_model
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed

User = get_user_model()

class SimpleBearerAuthentication(BaseAuthentication):
    keyword = b'Bearer'

    def authenticate(self, request):
        auth = get_authorization_header(request).split()
        if not auth or auth[0].lower() != self.keyword.lower():
            return None  # 他の認証にフォールバック

        if len(auth) != 2:
            raise AuthenticationFailed('Invalid Authorization header')

        token = auth[1].decode('utf-8')

        try:
            data = signing.loads(
                token,
                salt=settings.SIMPLE_TOKEN_SALT,
                max_age=getattr(settings, 'SIMPLE_TOKEN_TTL_SECONDS', 900),  # 期限チェック
            )
        except signing.SignatureExpired:
            raise AuthenticationFailed('Token expired')
        except signing.BadSignature:
            raise AuthenticationFailed('Bad token')

        try:
            user = User.objects.get(pk=data['u'])
        except User.DoesNotExist:
            raise AuthenticationFailed('User not found')

        if not getattr(user, 'is_staff', False):
            raise AuthenticationFailed('Not admin')

        return (user, None)
