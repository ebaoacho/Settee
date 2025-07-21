from django.db import models
from django.contrib.postgres.fields import ArrayField
from django.contrib.auth.hashers import make_password
from django.utils import timezone
from datetime import date, timedelta

class UserProfile(models.Model):
    """
    Flutter から受け取る会員登録情報を格納するテーブル。

    フィールド一覧：
      - id              : AutoField（主キー、自動増分）
      - phone           : 電話番号（文字列）
      - email           : メールアドレス（EmailField、ユニーク）
      - gender          : 性別（"男性" または "女性"）
      - birth_date      : 生年月日（DateField）
      - nickname        : ニックネーム（文字列）
      - user_id         : ユーザーID（文字列、ユニーク）
      - password        : パスワード（ハッシュ化済文字列）
      - selected_stations: よく遊ぶ駅（文字列リスト、ArrayField）
      - match_multiple  : マッチする人数（False＝ひとり、True＝みんなで）
    """

    # ────────────────────────────────────────────
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

    # PostgreSQL の ArrayField を使って「よく遊ぶ駅」を文字列のリストとして保持
    # "池袋", "新宿", "渋谷", "横浜"の4つの値のみが入る想定
    # 例: ["池袋", "新宿", "渋谷", "横浜"] のようなリストを受け取れる
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
    
    occupation = models.CharField(  # 職業
        max_length=50,
        null=True,
        blank=True,
        help_text="職業（任意）"
    )

    university = models.CharField(  # 大学名
        max_length=100,
        null=True,
        blank=True,
        help_text="大学名（任意）"
    )

    blood_type = models.CharField(  # 血液型
        max_length=3,
        null=True,
        blank=True,
        help_text="血液型（例：A型、B型、O型、AB型）"
    )

    height = models.CharField(  # 身長
        max_length=10,
        null=True,
        blank=True,
        help_text="身長（例：170cm）"
    )

    drinking = models.CharField(  # 飲酒習慣
        max_length=50,
        null=True,
        blank=True,
        help_text="お酒（例：飲まない、たまに飲む、よく飲む）"
    )

    smoking = models.CharField(  # 喫煙習慣
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
    
    def clean_available_dates(self):
        today = date.today()
        week_dates = [today + timedelta(days=i) for i in range(7)]
        # データが空（新規ユーザーなど）の場合 → デフォルトで全部暇
        if not self.available_dates:
            self.available_dates = week_dates
        else:
            # 保存された日付から未来7日間内のみ残す
            self.available_dates = sorted([
                d for d in self.available_dates if d in week_dates
            ])

    def __str__(self):
        return f"{self.nickname} ({self.email})"

    def save(self, *args, **kwargs):
        self.clean_available_dates()
        # パスワードの処理はそのまま
        raw = self.password
        if raw and (not raw.startswith('pbkdf2_sha256$')):
            self.password = make_password(raw)
        super().save(*args, **kwargs)

    class Meta:
        db_table = "user_profile"
        verbose_name = "ユーザープロファイル"
        verbose_name_plural = "ユーザープロファイル一覧"

class LikeAction(models.Model):
    sender = models.ForeignKey('UserProfile', related_name='sent_likes', on_delete=models.CASCADE)
    receiver = models.ForeignKey('UserProfile', related_name='received_likes', on_delete=models.CASCADE)
    like_type = models.IntegerField()  # 0: Like, 1: Super Like, 2: ごちそうLike, 3: メッセージLike
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        unique_together = ('sender', 'receiver')
        
    def __str__(self):
        return f"{self.sender.user_id} → {self.receiver.user_id} ({self.like_type})"
    
class Message(models.Model):
    sender = models.ForeignKey('UserProfile', on_delete=models.CASCADE, related_name='sent_messages')
    receiver = models.ForeignKey('UserProfile', on_delete=models.CASCADE, related_name='received_messages')
    text = models.TextField()
    timestamp = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['timestamp']

    def __str__(self):
        return f"{self.sender.nickname} -> {self.receiver.nickname}: {self.content[:20]}"