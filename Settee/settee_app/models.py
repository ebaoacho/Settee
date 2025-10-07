from django.db import models
from django.contrib.postgres.fields import ArrayField
from django.contrib.auth.hashers import make_password
from django.utils import timezone
from datetime import date, timedelta
from django.core.exceptions import ValidationError
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.conf import settings

class UserProfile(models.Model):
    """
    Flutter から受け取る会員登録情報を格納するテーブル。

    フィールド一覧：
      - id               : AutoField（主キー、自動増分）
      - phone            : 電話番号（文字列）
      - email            : メールアドレス（EmailField、ユニーク）
      - gender           : 性別（"男性" または "女性"）
      - birth_date       : 生年月日（DateField）
      - nickname         : ニックネーム（文字列）
      - user_id          : ユーザーID（文字列、ユニーク）
      - password         : パスワード（ハッシュ化済文字列）
      - selected_area    : よく遊ぶ駅（文字列リスト、ArrayField）
      - match_multiple   : マッチする人数（False＝ひとり、True＝みんなで）
      - occupation       : 職業（任意）
      - university       : 大学名（任意）
      - blood_type       : 血液型（任意）
      - height           : 身長（任意）
      - drinking         : 飲酒習慣（任意）
      - smoking          : 喫煙習慣（任意）
      - available_dates  : 会える日付リスト
      - zodiac           : 星座（任意）         ← 追加
      - mbti             : MBTI（任意）         ← 追加
      - seeking          : 求めているのは（任意）← 追加（自由記述）
      - preference       : 好み（任意）         ← 追加（自由記述）
    """

    phone = models.CharField(
        max_length=20,
        unique=True,
        help_text="電話番号（ハイフン含めても可）"
    )

    email = models.EmailField(
        max_length=254,
        unique=True,
        help_text="メールアドレス（ユニーク）"
    )

    GENDER_CHOICES = [
        ('男性', '男性'),
        ('女性', '女性'),
    ]
    gender = models.CharField(
        max_length=2,
        choices=GENDER_CHOICES,
        help_text="性別（'男性' または '女性'）"
    )

    birth_date = models.DateField(
        help_text="生年月日（YYYY-MM-DD）"
    )

    nickname = models.CharField(
        max_length=50,
        help_text="ニックネーム"
    )

    user_id = models.CharField(
        max_length=100,
        unique=True,
        help_text="アプリ内でのユーザーID（ユニーク）"
    )

    password = models.CharField(
        max_length=128,
        help_text="ハッシュ化済みパスワード"
    )

    # 駅のリスト
    selected_area = ArrayField(
        base_field=models.CharField(max_length=50),
        blank=True,
        default=list,
        help_text="よく遊ぶ駅のリスト（複数選択可）"
    )

    match_multiple = models.BooleanField(
        default=False,
        help_text="マッチする人数（False＝ひとり、True＝みんなで）"
    )

    occupation = models.CharField(
        max_length=50,
        null=True,
        blank=True,
        help_text="職業（任意）"
    )

    university = models.CharField(
        max_length=100,
        null=True,
        blank=True,
        help_text="大学名（任意）"
    )

    blood_type = models.CharField(
        max_length=3,
        null=True,
        blank=True,
        help_text="血液型（例：A型、B型、O型、AB型）"
    )

    height = models.CharField(
        max_length=10,
        null=True,
        blank=True,
        help_text="身長（例：170cm）"
    )

    drinking = models.CharField(
        max_length=50,
        null=True,
        blank=True,
        help_text="お酒（例：飲まない、たまに飲む、よく飲む）"
    )

    smoking = models.CharField(
        max_length=50,
        null=True,
        blank=True,
        help_text="煙草（例：吸わない、たまに吸う、吸う）"
    )

    available_dates = ArrayField(
        base_field=models.DateField(),
        blank=True,
        default=list,
        help_text="会える日付リスト"
    )

    # ==== ここから追加フィールド ====
    ZODIAC_CHOICES = [
        ('おひつじ座', 'おひつじ座'),
        ('おうし座', 'おうし座'),
        ('ふたご座', 'ふたご座'),
        ('かに座', 'かに座'),
        ('しし座', 'しし座'),
        ('おとめ座', 'おとめ座'),
        ('てんびん座', 'てんびん座'),
        ('さそり座', 'さそり座'),
        ('いて座', 'いて座'),
        ('やぎ座', 'やぎ座'),
        ('みずがめ座', 'みずがめ座'),
        ('うお座', 'うお座'),
    ]
    zodiac = models.CharField(
        max_length=10,
        choices=ZODIAC_CHOICES,
        null=True,
        blank=True,
        help_text="星座（任意）"
    )

    MBTI_CHOICES = [
        ('INTJ','INTJ'),('INTP','INTP'),('ENTJ','ENTJ'),('ENTP','ENTP'),
        ('INFJ','INFJ'),('INFP','INFP'),('ENFJ','ENFJ'),('ENFP','ENFP'),
        ('ISTJ','ISTJ'),('ISFJ','ISFJ'),('ESTJ','ESTJ'),('ESFJ','ESFJ'),
        ('ISTP','ISTP'),('ISFP','ISFP'),('ESTP','ESTP'),('ESFP','ESFP'),
    ]
    mbti = models.CharField(
        max_length=4,
        choices=MBTI_CHOICES,
        null=True,
        blank=True,
        help_text="MBTI（任意）"
    )

    seeking = models.TextField(
        null=True,
        blank=True,
        help_text="求めているのは（自由記述・任意）"
    )

    preference = models.TextField(
        null=True,
        blank=True,
        help_text="好み（自由記述・任意）"
    )
    
    # 既存のエンタイトルメント系
    settee_points = models.IntegerField(default=0)
    boost_until = models.DateTimeField(null=True, blank=True)
    private_mode_until = models.DateTimeField(null=True, blank=True)

    # 既存：メッセージ／スーパーの残数
    message_like_credits = models.PositiveIntegerField(default=0)
    super_like_credits   = models.PositiveIntegerField(default=0)

    # === Treat Like 残数（VIP月次・チケット加算用） ===
    treat_like_credits   = models.PositiveIntegerField(default=0)

    # 既存：Plus の有効期限
    settee_plus_until = models.DateTimeField(null=True, blank=True)

    # === VIP の有効期限 ===
    settee_vip_until  = models.DateTimeField(null=True, blank=True)

    # === Normal の12時間リセット制御（旧10→35/12h） ===
    normal_like_remaining = models.PositiveIntegerField(default=35)
    normal_like_reset_at  = models.DateTimeField(null=True, blank=True)

    # === VIPの月次リセット制御（YYYYMMを数値で保持） ===
    vip_counters_month = models.PositiveIntegerField(null=True, blank=True)  # 例: 202501

    # === チケット等の恒久ボーナス枠（「単純加算」方針を月次リセットに反映させるため） ===
    bonus_super_like_credits   = models.PositiveIntegerField(default=0)
    bonus_message_like_credits = models.PositiveIntegerField(default=0)
    bonus_treat_like_credits   = models.PositiveIntegerField(default=0)

    refine_unlocked = models.BooleanField(default=False)
    
    # === プラン別の定数 ===
    NORMAL_LIKES_PER_WINDOW = 35
    NORMAL_LIKE_WINDOW_HOURS = 12

    VIP_BASE_SUPER_PER_MONTH   = 10
    VIP_BASE_TREAT_PER_MONTH   = 10
    VIP_BASE_MESSAGE_PER_MONTH = 10
    
    is_banned = models.BooleanField(default=False)

    def clean_available_dates(self):
        today = date.today()
        week_dates = [today + timedelta(days=i) for i in range(7)]
        if not self.available_dates:
            self.available_dates = week_dates
        else:
            self.available_dates = sorted([d for d in self.available_dates if d in week_dates])

    def __str__(self):
        return f"{self.nickname} ({self.email})"

    def save(self, *args, **kwargs):
        self.clean_available_dates()
        raw = self.password
        if raw and (not raw.startswith('pbkdf2_sha256$')):
            self.password = make_password(raw)
        super().save(*args, **kwargs)
        
    @property
    def now(self):
        return timezone.now()

    @property
    def is_plus_active(self) -> bool:
        return bool(self.settee_plus_until and self.settee_plus_until > self.now)

    @property
    def is_vip_active(self) -> bool:
        return bool(self.settee_vip_until and self.settee_vip_until > self.now)

    @property
    def like_unlimited(self) -> bool:
        # Plus と VIP は通常Like無制限
        return self.is_plus_active or self.is_vip_active

    @property
    def boost_active(self) -> bool:
        # 要件：Normal=オフ, Plus=オフ, VIP=オン
        # 既存の boost_until も併用可能に（柔軟運用）
        return self.is_vip_active or (self.boost_until and self.boost_until > self.now)

    @property
    def private_mode_active(self) -> bool:
        # 要件：Normal=オフ, Plus=オン, VIP=オン
        return self.is_plus_active or self.is_vip_active or (self.private_mode_until and self.private_mode_until > self.now)

    @property
    def backtrack_enabled(self) -> bool:
        # 要件：Normal=オフ, Plus=オフ, VIP=オン
        return self.is_vip_active

    # ───────── 自動リセット系（アクセス時に整える）─────────
    def _ensure_normal_window(self, *, save: bool = True):
        """Normal用：12時間ごとの残数ウィンドウを維持（無制限のときは触らない）"""
        if self.like_unlimited:
            return
        now = self.now
        # 初回 or 期限切れ → リセット
        if not self.normal_like_reset_at or self.normal_like_reset_at <= now or self.normal_like_remaining is None:
            self.normal_like_remaining = self.NORMAL_LIKES_PER_WINDOW
            self.normal_like_reset_at  = now + timedelta(hours=self.NORMAL_LIKE_WINDOW_HOURS)
            if save:
                self.save(update_fields=['normal_like_remaining', 'normal_like_reset_at'])

    def _ensure_vip_month(self, *, save: bool = True):
        """
        VIP用：月替わりで Super/Treat/Message を“加算”する（リセットしない・繰り越し）。
        - 毎月の加算量 = ベース(10) + bonus_*（チケットの恒久加算分）
        - vip_counters_month が古ければ、その差分の月数だけまとめて加算
        """
        if not self.is_vip_active:
            return

        now = self.now
        yyyymm_now = now.year * 100 + now.month

        # 直近の反映月が未設定なら「今月ぶんを1回だけ」加算する
        if not self.vip_counters_month:
            months = 1
        else:
            prev = self.vip_counters_month
            prev_year, prev_month = divmod(prev, 100)
            months = (now.year - prev_year) * 12 + (now.month - prev_month)
            if months <= 0:
                return  # 同月内は何もしない

        # 毎月の加算量（ベース10 + チケットの恒久ボーナス）
        monthly_super   = self.VIP_BASE_SUPER_PER_MONTH   + self.bonus_super_like_credits
        monthly_treat   = self.VIP_BASE_TREAT_PER_MONTH   + self.bonus_treat_like_credits
        monthly_message = self.VIP_BASE_MESSAGE_PER_MONTH + self.bonus_message_like_credits

        # 差分月数分を“加算”（繰り越しを残したまま増やす）
        self.super_like_credits   += monthly_super   * months
        self.treat_like_credits   += monthly_treat   * months
        self.message_like_credits += monthly_message * months

        self.vip_counters_month = yyyymm_now

        if save:
            self.save(update_fields=[
                'vip_counters_month',
                'super_like_credits', 'treat_like_credits', 'message_like_credits'
            ])

    def ensure_quotas_now(self, *, save=True):
        """
        外部（APIビューなど）から呼んで、その時点の権利を“正”に整える。
        - Normal: 12時間ウィンドウを必要ならリセット
        - VIP   : 月次カウンタを必要ならリセット
        - Plus  : 何もしない（無制限・各クレジットは0のままでOK）
        """
        self._ensure_normal_window(save=save)
        self._ensure_vip_month(save=save)

    # ───────── 付与（チケットの“単純加算”）─────────
    def grant_ticket_credits(self, *, super_n=0, message_n=0, treat_n=0, save=True):
        """
        チケット効果で初期クレジットがある場合に“単純加算”する。
        さらに毎月の自動リセットで消えないよう、bonus_* にも反映。
        """
        if super_n:
            self.super_like_credits += super_n
            self.bonus_super_like_credits += super_n
        if message_n:
            self.message_like_credits += message_n
            self.bonus_message_like_credits += message_n
        if treat_n:
            self.treat_like_credits += treat_n
            self.bonus_treat_like_credits += treat_n
        if save:
            self.save(update_fields=[
                'super_like_credits', 'message_like_credits', 'treat_like_credits',
                'bonus_super_like_credits', 'bonus_message_like_credits', 'bonus_treat_like_credits'
            ])

    # ───────── 消費（成功時 True を返す）─────────
    def consume_like(self, like_type: int, *, save=True) -> bool:
        """
        like_type: LikeType.NORMAL / SUPER / TREAT / MESSAGE
        仕様：
          - Normal: Plus/VIP→無制限で常にOK。Normal→残数を1減（0なら不可）
          - SUPER/TREAT/MESSAGE: 残数を1減（0なら不可）。Plusは仕様上オフ（残数0のまま）
        """
        self.ensure_quotas_now(save=False)

        if like_type == LikeType.NORMAL:
            if self.like_unlimited:
                return True
            if self.normal_like_remaining and self.normal_like_remaining > 0:
                self.normal_like_remaining -= 1
                if save:
                    self.save(update_fields=['normal_like_remaining'])
                return True
            return False

        if like_type == LikeType.SUPER:
            if self.super_like_credits > 0:
                self.super_like_credits -= 1
                if save:
                    self.save(update_fields=['super_like_credits'])
                return True
            return False

        if like_type == LikeType.TREAT:
            if self.treat_like_credits > 0:
                self.treat_like_credits -= 1
                if save:
                    self.save(update_fields=['treat_like_credits'])
                return True
            return False

        if like_type == LikeType.MESSAGE:
            if self.message_like_credits > 0:
                self.message_like_credits -= 1
                if save:
                    self.save(update_fields=['message_like_credits'])
                return True
            return False

        return False  # 未知タイプ

    # ───────── クライアント用に現在の権利をまとめて返す（APIでそのまま返しやすい）─────────
    def get_entitlements(self) -> dict:
        """
        例：/users/{user_id}/entitlements/ のレスポンスとして返却しやすい形。
        """
        self.ensure_quotas_now(save=False)
        return {
            'tier':  'VIP' if self.is_vip_active else ('PLUS' if self.is_plus_active else 'NORMAL'),
            'like_unlimited': self.like_unlimited,
            'normal_like_remaining': None if self.like_unlimited else self.normal_like_remaining,
            'normal_like_reset_at': None if self.like_unlimited else self.normal_like_reset_at,
            'super_like_credits':   self.super_like_credits,
            'treat_like_credits':   self.treat_like_credits,
            'message_like_credits': self.message_like_credits,
            'backtrack_enabled':    self.backtrack_enabled,
            'boost_active':         self.boost_active,
            'private_mode_active':  self.private_mode_active,
            # 互換用：既存フロントの想定キー（必要に応じて）
            'settee_plus_active':   self.is_plus_active,
        }

    class Meta:
        db_table = "user_profile"
        verbose_name = "ユーザープロファイル"
        verbose_name_plural = "ユーザープロファイル一覧"

class LikeType(models.IntegerChoices):
    NORMAL   = 0, "Normal"
    SUPER    = 1, "Super"
    TREAT    = 2, "Treat"
    MESSAGE  = 3, "Message"

class LikeAction(models.Model):
    sender     = models.ForeignKey(
        'UserProfile', related_name='sent_likes', on_delete=models.CASCADE
    )
    receiver   = models.ForeignKey(
        'UserProfile', related_name='received_likes', on_delete=models.CASCADE
    )
    like_type  = models.IntegerField(choices=LikeType.choices, db_index=True)

    # ── メッセージLike用の本文と送信時刻
    # MESSAGE 以外のLikeでは空のままでOK
    message         = models.TextField(null=True, blank=True)   # 必要に応じて CharField(max_length=500) でも可
    message_sent_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    # ── 更新時刻（本文編集や種別変更時に自動更新）
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        # 1人→1人に対してエントリは1本だけ（重複Likeを防止）
        # 既に通常Likeがある相手にメッセージLikeを送る場合は、
        # 新規作成ではなく既存行を MESSAGE に“昇格”し、message を埋める運用想定。
        unique_together = ('sender', 'receiver')
        indexes = [
            models.Index(fields=['receiver', '-created_at']),
        ]
        ordering = ['-created_at']

    def __str__(self):
        # 退会後は None になり得るので安全に
        s = getattr(self.sender, 'user_id', 'DELETED')
        r = getattr(self.receiver, 'user_id', 'DELETED')
        return f"{s} → {r} ({self.get_like_type_display()})"

    # 任意: バリデーション（DRF Serializer 等で full_clean() を呼ぶ場合に有効）
    def clean(self):
        # MESSAGE のときは message を必須にする
        if self.like_type == LikeType.MESSAGE:
            if not (self.message and self.message.strip()):
                raise ValidationError({'message': 'メッセージLikeでは message は必須です。'})

    # 便利プロパティ
    @property
    def has_message(self) -> bool:
        return bool(self.message and self.message.strip())

class Match(models.Model):
    """
    マッチング成立を記録するテーブル
    """
    # 実際にはどちらにも入る可能性あり
    user_lower_id = models.ForeignKey(
        'UserProfile', 
        related_name='matches_as_lower', 
        on_delete=models.CASCADE,
        help_text="IDが小さい方のユーザー"
    )
    user_higher_id = models.ForeignKey(
        'UserProfile', 
        related_name='matches_as_higher', 
        on_delete=models.CASCADE,
        help_text="IDが大きい方のユーザー"
    )
    matched_at = models.DateTimeField(auto_now_add=True)

    # 各ユーザーの既読状態
    lower_user_seen = models.BooleanField(default=False)
    lower_user_seen_at = models.DateTimeField(null=True, blank=True)
    
    higher_user_seen = models.BooleanField(default=False)
    higher_user_seen_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'match'
        unique_together = ('user_lower_id', 'user_higher_id')
        indexes = [
            models.Index(fields=['user_lower_id', 'lower_user_seen']),
            models.Index(fields=['user_higher_id', 'higher_user_seen']),
            models.Index(fields=['-matched_at']),
        ]
        constraints = [
            models.CheckConstraint(
                check=models.Q(user_lower_id__lt=models.F('user_higher_id')),
                name='match_user_order'
            )
        ]
    
    def __str__(self):
        return f"{self.user_lower_id.user_id} ⇄ {self.user_higher_id.user_id}"

    @classmethod
    def create_match(cls, user1, user2):
        """
        一旦の対処として、user1をlower、user2をhigherとして保存
        user_idが文字列なので、IDでの比較は意味がない
        """
        return cls.objects.create(user_lower_id=user1, user_higher_id=user2)
    
    @classmethod
    def get_match(cls, user1, user2):
        # user_idが文字列なので、一旦の対処として2つのクエリを発行
        try:
            # user1がlower、user2がhigherの場合
            return cls.objects.get(user_lower_id=user1, user_higher_id=user2)
        except cls.DoesNotExist:
            try:
                # user1がhigher、user2がlowerの場合
                return cls.objects.get(user_lower_id=user2, user_higher_id=user1)
            except cls.DoesNotExist:
                raise cls.DoesNotExist

    def mark_seen_by(self, user):
        """
        特定ユーザーが既読にする
        user.idは主キーなので、FKとの比較は正しく動作する
        """
        now = timezone.now()
        if user.id == self.user_lower_id_id:  # 主キーでの比較
            self.lower_user_seen = True
            self.lower_user_seen_at = now
            self.save(update_fields=['lower_user_seen', 'lower_user_seen_at'])
        elif user.id == self.user_higher_id_id:  # 主キーでの比較
            self.higher_user_seen = True
            self.higher_user_seen_at = now
            self.save(update_fields=['higher_user_seen', 'higher_user_seen_at'])

class ConversationKind(models.TextChoices):
    DM     = 'dm',     'Direct'
    DOUBLE = 'double', 'DoubleMatch'   # 「みんなでマッチ」用
    GROUP  = 'group',  'Group'         # 任意のグループ

class Conversation(models.Model):
    kind       = models.CharField(max_length=10, choices=ConversationKind.choices,
                                  default=ConversationKind.DM, db_index=True)
    title      = models.CharField(max_length=120, blank=True)
    created_by = models.ForeignKey('UserProfile', null=True, blank=True,
                                   on_delete=models.SET_NULL, related_name='conversations_created')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_message_at = models.DateTimeField(null=True, blank=True, db_index=True)

    # Double/Single の“マッチ相手”情報を残したい場合
    matched_pair_a = models.ForeignKey('UserProfile', null=True, blank=True,
                                       on_delete=models.SET_NULL, related_name='+')
    matched_pair_b = models.ForeignKey('UserProfile', null=True, blank=True,
                                       on_delete=models.SET_NULL, related_name='+')

    class Meta:
        indexes = [
            models.Index(fields=['kind', 'last_message_at']),
        ]

    def __str__(self):
        return f"[{self.kind}] {self.title or self.pk}"

    # 便利メソッド
    def add_member(self, user, role='member'):
        return ConversationMember.objects.get_or_create(conversation=self, user=user, defaults={'role': role})[0]

    def touch(self, at=None):
        self.last_message_at = at or timezone.now()
        self.save(update_fields=['last_message_at', 'updated_at'])

class ConversationMember(models.Model):
    conversation = models.ForeignKey(Conversation, related_name='members',
                                     on_delete=models.CASCADE)
    user         = models.ForeignKey('UserProfile', related_name='conversation_memberships',
                                     on_delete=models.CASCADE)
    role         = models.CharField(max_length=10, default='member')  # 'owner' / 'admin' / 'member'
    is_muted     = models.BooleanField(default=False)
    joined_at    = models.DateTimeField(auto_now_add=True)
    left_at      = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = (('conversation', 'user'),)
        indexes = [
            models.Index(fields=['user']),
            models.Index(fields=['conversation']),
            models.Index(fields=['conversation', 'left_at']),
        ]

    def __str__(self):
        return f"{self.user_id} in {self.conversation_id}"

class Message(models.Model):
    conversation = models.ForeignKey(Conversation, related_name='messages',
                                     on_delete=models.CASCADE)
    sender       = models.ForeignKey('UserProfile', related_name='sent_messages',
                                     on_delete=models.SET_NULL, null=True, blank=True)
    text         = models.TextField()
    # 画像などを載せたい場合に備えた汎用ペイロード
    extra        = models.JSONField(null=True, blank=True)
    created_at   = models.DateTimeField(default=timezone.now, db_index=True)
    edited_at    = models.DateTimeField(null=True, blank=True)
    deleted_at   = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['created_at']
        indexes = [
            models.Index(fields=['conversation', 'created_at']),
        ]

    def __str__(self):
        s = getattr(self.sender, 'nickname', '退会済み')
        return f"[{self.conversation_id}] {s}: {self.text[:20]}"

class MessageRead(models.Model):
    """
    既読管理：各メッセージに対する既読レシート。
    大規模化が見込まれる場合は「会話ごとの既読ポインタ（last_read_at/last_read_message）」に変える設計も可。
    """
    message = models.ForeignKey(Message, related_name='receipts', on_delete=models.CASCADE)
    user    = models.ForeignKey('UserProfile', related_name='message_receipts', on_delete=models.CASCADE)
    read_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = (('message', 'user'),)
        indexes = [
            models.Index(fields=['user', 'read_at']),
            models.Index(fields=['message']),
        ]

    def __str__(self):
        return f"read {self.message_id} by {self.user_id}"

@receiver(post_save, sender=Message)
def _update_conversation_on_new_message(sender, instance: Message, created, **kwargs):
    if created and instance.conversation_id:
        Conversation.objects.filter(id=instance.conversation_id).update(
            last_message_at=instance.created_at, updated_at=timezone.now()
        )

class Block(models.Model):
    blocker = models.ForeignKey('UserProfile', related_name='blocks_made', on_delete=models.CASCADE)
    blocked = models.ForeignKey('UserProfile', related_name='blocks_received', on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('blocker', 'blocked')

class UserTicket(models.Model):
    """
    ユーザに紐づく交換済みチケット。
    効果は ticket_code に応じてサーバ側で条件分岐して適用。
    """
    TICKET_CODE_CHOICES = (
        (1, 'BOOST_24H'),
        (2, 'REFINE_UNLOCK'),
        (3, 'PRIVATE_365D'),
        (4, 'MESSAGE_LIKE_5'),
        (5, 'SUPER_LIKE_5'),
        (6, 'SETTEE_PLUS_1DAY'),
    )

    STATUS_CHOICES = (
        ('unused', 'unused'),
        ('used', 'used'),
        ('expired', 'expired'),
    )

    user = models.ForeignKey(UserProfile, related_name='tickets', on_delete=models.CASCADE)
    ticket_code = models.PositiveSmallIntegerField(choices=TICKET_CODE_CHOICES)
    status = models.CharField(max_length=8, choices=STATUS_CHOICES, default='unused')
    acquired_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    used_at = models.DateTimeField(null=True, blank=True)
    source = models.CharField(max_length=20, null=True, blank=True)

    class Meta:
        db_table = 'user_ticket'
        indexes = [
            models.Index(fields=['user', 'status']),
        ]

    def __str__(self):
        return f"{self.user.user_id} code={self.ticket_code} ({self.status})"

class ImageAsset(models.Model):
    user = models.ForeignKey('UserProfile', on_delete=models.CASCADE, related_name='images')
    filename = models.CharField(max_length=255)
    url = models.CharField(max_length=255)
    image_index = models.PositiveIntegerField(default=1)
    reviewed = models.BooleanField(default=False)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='reviewed_images'
    )
    moderation_status = models.CharField(
        max_length=16, default='pending'
    )  # 'pending' | 'approved'（要件に合わせて最小限）
    report_count = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['user', 'filename'], name='uniq_user_filename'),
        ]
        indexes = [
            models.Index(fields=['user', 'image_index']),
        ]

    def mark_reviewed(self, admin_user=None, approved=True):
        """必ずDBに保存して確定させる"""
        self.reviewed = True
        self.reviewed_at = timezone.now()
        self.reviewed_by = admin_user
        self.moderation_status = 'approved' if approved else 'pending'
        self.save(update_fields=['reviewed', 'reviewed_at', 'reviewed_by', 'moderation_status', 'updated_at'])

    def mark_unreviewed(self):
        """必ずDBに保存して確定させる"""
        self.reviewed = False
        self.reviewed_at = None
        self.reviewed_by = None
        self.moderation_status = 'pending'
        self.save(update_fields=['reviewed', 'reviewed_at', 'reviewed_by', 'moderation_status', 'updated_at'])

    def __str__(self):
        return f'{self.user.user_id}:{self.filename} ({ "✔" if self.reviewed else "…" })'
    
class Report(models.Model):
    """
    通報レコード（通報者情報・画像情報は保持しない）
    - target_user: 通報対象ユーザー
    - reason: 通報理由（任意）
    - read: 管理側で既読化したフラグ（未読UI用）
    """
    target_user = models.ForeignKey(
        'UserProfile', related_name='reports_received',
        on_delete=models.CASCADE
    )
    reason = models.TextField(blank=True, default='')
    read = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = 'report'
        indexes = [
            models.Index(fields=['target_user', 'read']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"Report(id={self.id}, target={self.target_user.user_id}, read={self.read})"