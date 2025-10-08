import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'user_profile_screen.dart';

// ================== 共有定義（Match表示） ==================

enum MatchMode { single, double }

class MatchUser {
  final String userId;
  final String? avatarUrl;
  final String? displayName;
  const MatchUser({required this.userId, this.avatarUrl, this.displayName});
}

// ================== Matchバナー（チャット上部） ==================

class MatchBanner extends StatefulWidget {
  final MatchMode mode;
  final MatchUser self;
  final MatchUser partner;
  final MatchUser? myInvitee;
  final MatchUser? partnerInvitee;
  final Future<bool> Function(String inviteeUserId)? onInvite; // nullなら招待UIは出さない

  const MatchBanner({
    super.key,
    required this.mode,
    required this.self,
    required this.partner,
    this.myInvitee,
    this.partnerInvitee,
    this.onInvite,
  });

  @override
  State<MatchBanner> createState() => _MatchBannerState();
}

class _MatchBannerState extends State<MatchBanner> {
  double? _bgAspect; // 背景画像の width/height
  late MatchUser? _myInvitee;
  late MatchUser? _partnerInvitee;
  bool _inviting = false;

  // DoubleMatch の相対座標とサイズ（画像基準 0.0〜1.0）
  static const _doublePositions = <String, Offset>{
    // 左上=相手、右上=相手が招待、左下=自分、右下=自分が招待
    'partner'       : Offset(0.27, 0.28),
    'partnerFriend' : Offset(0.71, 0.28),
    'self'          : Offset(0.26, 0.83),
    'myFriend'      : Offset(0.71, 0.83),
  };
  static const _doubleAvatarDiameterFrac = 0.30;

  // SingleMatch（招待なし）
  static const _singlePositions = <String, Offset>{
    'self'    : Offset(0.30, 0.58),
    'partner' : Offset(0.70, 0.58),
  };
  static const _singleAvatarDiameterFracMain = 0.30;

  @override
  void initState() {
    super.initState();
    _myInvitee = widget.myInvitee;
    _partnerInvitee = widget.partnerInvitee;
    _loadAspect();
  }

  Future<void> _loadAspect() async {
    final asset = widget.mode == MatchMode.double
        ? 'assets/DoubleMatch.png'
        : 'assets/SingleMatch.png';
    try {
      final img = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(img.buffer.asUint8List());
      final fi = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _bgAspect = fi.image.width / fi.image.height);
    } catch (_) {
      if (mounted) setState(() => _bgAspect = 9 / 16); // フォールバック
    }
  }

  Future<void> _openInviteDialog() async {
    if (widget.onInvite == null) return;
    final controller = TextEditingController();
    final inviteeId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101010),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('友だちを招待', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ユーザーIDを入力',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('招待する')),
        ],
      ),
    );
    if (inviteeId == null || inviteeId.isEmpty) return;

    setState(() => _inviting = true);
    final ok = await widget.onInvite!(inviteeId).catchError((_) => false);
    if (!mounted) return;
    setState(() => _inviting = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('招待に失敗しました')));
      return;
    }
    setState(() {
      _myInvitee = MatchUser(userId: inviteeId, avatarUrl: null, displayName: 'Friend');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgAsset = widget.mode == MatchMode.double
        ? 'assets/DoubleMatch.png'
        : 'assets/SingleMatch.png';

    // 親（スリバー）から横幅いっぱいで置かれることを想定。
    // 横幅=最大、 高さ=幅/比率 で厳密に作る → 横に余白は絶対出ない。
    return LayoutBuilder(
      builder: (context, c) {
        final ratio = _bgAspect ?? (9 / 16);
        final w = c.maxWidth;      // 横幅は最大
        final h = w / ratio;       // アスペクト比から高さを確定

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bgAsset, fit: BoxFit.fitWidth, alignment: Alignment.center),
              _buildOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverlay() {
    switch (widget.mode) {
      case MatchMode.double:
        return _DoubleOverlay(
          self: widget.self,
          partner: widget.partner,
          myInvitee: _myInvitee,
          partnerInvitee: _partnerInvitee,
          onInviteTap: _openInviteDialog,
        );
      case MatchMode.single:
        return _SingleOverlay(
          self: widget.self,
          partner: widget.partner,
        );
    }
  }
}

// ========== 丸アバター & プレースホルダー（相対配置用） ==========

class _AvatarCircle extends StatelessWidget {
  final String? url;
  final double size;
  const _AvatarCircle({required this.url, required this.size});

  Widget _placeholder() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF444444)),
        child: const Icon(Icons.person, color: Colors.white70),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.03),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: (url == null || url!.isNotEmpty == false)
          ? _placeholder()
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            ),
    );
  }
}

class _InvitePlaceholder extends StatelessWidget {
  final String message;
  final double size;
  final bool showPlus;
  final VoidCallback? onPlus;

  const _InvitePlaceholder({
    required this.message,
    required this.size,
    required this.showPlus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final plusSize = size * 0.28;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 本体（灰丸）
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Color(0xFF7B7B7B),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  fontSize: size * 0.09, // 相対フォント
                ),
              ),
            ),
          ),
          // 白の点線枠
          Positioned.fill(
            child: CustomPaint(
              painter: _DottedCirclePainter(
                color: Colors.white,
                dotCount: 48,
                strokeWidth: size * 0.016,
              ),
            ),
          ),
          // 右下の＋ボタン
          if (showPlus)
            Positioned(
              right: -plusSize * 0.15,
              bottom: -plusSize * 0.10,
              child: GestureDetector(
                onTap: onPlus,
                child: Container(
                  width: plusSize,
                  height: plusSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6E6E6),
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: const Icon(Icons.add, color: Colors.black87),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  final Color color;
  final int dotCount;
  final double strokeWidth;
  const _DottedCirclePainter({required this.color, required this.dotCount, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final dotR = strokeWidth; // ドット半径
    for (int i = 0; i < dotCount; i++) {
      final t = (i / dotCount) * 2 * math.pi;
      final p = center + Offset(math.cos(t), math.sin(t)) * (r - dotR * 0.8);
      canvas.drawCircle(p, dotR, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dotCount != dotCount || oldDelegate.strokeWidth != strokeWidth;
}

// ========== Double / Single のオーバーレイ実装 ==========

class _DoubleOverlay extends StatelessWidget {
  final MatchUser self, partner;
  final MatchUser? myInvitee, partnerInvitee;
  final VoidCallback? onInviteTap;

  const _DoubleOverlay({
    required this.self,
    required this.partner,
    required this.myInvitee,
    required this.partnerInvitee,
    required this.onInviteTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final d = c.maxWidth * _MatchBannerState._doubleAvatarDiameterFrac;

      return Stack(children: [
        // 固定アバター
        _at(_AvatarCircle(url: self.avatarUrl, size: d), _MatchBannerState._doublePositions['self']!),
        _at(_AvatarCircle(url: partner.avatarUrl, size: d), _MatchBannerState._doublePositions['partner']!),

        // 相手側の招待スロット：未招待なら「○○さんの素敵な友だちを待とう」
        if (partnerInvitee != null)
          _at(_AvatarCircle(url: partnerInvitee!.avatarUrl, size: d), _MatchBannerState._doublePositions['partnerFriend']!)
        else
          _at(
            _InvitePlaceholder(
              message: '${partner.displayName ?? "相手"}さんの素敵な\n友だちを待とう',
              size: d,
              showPlus: false,
            ),
            _MatchBannerState._doublePositions['partnerFriend']!,
          ),

        // 自分側の招待スロット：未招待なら「あなたの友だちを招待しよう」＋ボタン
        if (myInvitee != null)
          _at(_AvatarCircle(url: myInvitee!.avatarUrl, size: d), _MatchBannerState._doublePositions['myFriend']!)
        else
          _at(
            _InvitePlaceholder(
              message: 'あなたの友だちを\n招待しよう',
              size: d,
              showPlus: true,
              onPlus: onInviteTap,
            ),
            _MatchBannerState._doublePositions['myFriend']!,
          ),
      ]);
    });
  }

  Widget _at(Widget child, Offset frac) => Positioned.fill(
        child: Align(alignment: Alignment(-1 + 2 * frac.dx, -1 + 2 * frac.dy), child: child),
      );
}

class _SingleOverlay extends StatelessWidget {
  final MatchUser self, partner;
  const _SingleOverlay({
    required this.self,
    required this.partner,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final dMain = c.maxWidth * _MatchBannerState._singleAvatarDiameterFracMain;
      return Stack(children: [
        _at(_AvatarCircle(url: self.avatarUrl, size: dMain), _MatchBannerState._singlePositions['self']!),
        _at(_AvatarCircle(url: partner.avatarUrl, size: dMain), _MatchBannerState._singlePositions['partner']!),
      ]);
    });
  }

  Widget _at(Widget child, Offset frac) => Positioned.fill(
        child: Align(alignment: Alignment(-1 + 2 * frac.dx, -1 + 2 * frac.dy), child: child),
      );
}

// ================== ChatScreen（スリバー化でオーバーフロー回避） ==================

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String matchedUserId;
  final String matchedUserNickname;

  // 追加：会話ID（あれば招待APIを叩く）
  final int? conversationId;

  // 追加：ヘッダの表示モード（既定は single）
  final MatchMode headerMode;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.matchedUserId,
    required this.matchedUserNickname,
    this.conversationId,
    this.headerMode = MatchMode.single,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<dynamic> messages = [];
  final TextEditingController _controller = TextEditingController();

  String? _selfAvatarUrl;
  String? _partnerAvatarUrl;
  Timer? _timer;

  final Map<String, String?> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    _prefetchAvatars();
    fetchMessages();
    // 5秒ごとにポーリング
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchMessages();
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // タイマーを停止してメモリリークを防ぐ
    _controller.dispose();
    super.dispose();
  }

  // ---- 1枚目アバターURLを“できるだけ確実に”返す（HEAD→GET Range）
  Future<String?> _resolveFirstAvatarUrl(String userId) async {
    final preferred = ['jpg','jpeg','png','JPG','JPEG','PNG'];
    final others    = ['heic','heif','HEIC','HEIF'];

    for (var i = 1; i <= 9; i++) {
      for (final ext in [...preferred, ...others]) {
        final uri = Uri.parse('https://settee.jp/images/$userId/${userId}_$i.$ext');
        try {
          final head = await http.head(uri).timeout(const Duration(seconds: 4));
          if (head.statusCode == 200) return uri.toString();
          if (head.statusCode == 405 || head.statusCode == 403) {
            final get = await http.get(uri, headers: {'Range': 'bytes=0-0'}).timeout(const Duration(seconds: 6));
            if (get.statusCode == 200 || get.statusCode == 206) return uri.toString();
          }
        } catch (_) {/* 次の候補へ */}
      }
    }
    return null;
  }


  // キャッシュに無ければ読み込む
  Future<void> _ensureAvatarLoaded(String userId) async {
    if (_avatarCache.containsKey(userId)) return;
    final url = await _resolveFirstAvatarUrl(userId);
    if (!mounted) return;
    setState(() => _avatarCache[userId] = url);
  }

  // シングル/ダブルに応じて事前に参加者をプリフェッチ
  Future<void> _prefetchAvatars() async {
    // 自分 & 1:1の相手
    await Future.wait([
      _ensureAvatarLoaded(widget.currentUserId),
      _ensureAvatarLoaded(widget.matchedUserId),
    ]);

    // ダブルマッチなら会話メンバーも事前読込（会話一覧APIからメンバー取得）
    if (widget.headerMode == MatchMode.double && widget.conversationId != null) {
      try {
        final uri = Uri.parse('https://settee.jp/conversations/user/${widget.currentUserId}/');
        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final items = jsonDecode(utf8.decode(res.bodyBytes)) as List;
          final me = widget.currentUserId;
          final cid = widget.conversationId.toString();
          for (final it in items) {
            if ('${it['id']}' != cid) continue;
            final members = (it['members'] as List?)?.map((e) => e.toString()).toList() ?? const [];
            for (final uid in members) {
              // 自分含む全員をキャッシュ
              await _ensureAvatarLoaded(uid);
            }
            break;
          }
        }
      } catch (_) {/* 無視 */}
    }
  }

  // 新着メッセージに含まれる送信者も都度ウォームアップ
  Future<void> _warmAvatarCacheFromMessages(List<dynamic> msgs) async {
    final ids = <String>{};
    for (final m in msgs) {
      final sid = '${m['sender']}';
      if (sid.isNotEmpty) ids.add(sid);
    }
    await Future.wait(ids.map(_ensureAvatarLoaded));
  }


  Future<void> fetchMessages() async {
    try {
      if (widget.headerMode == MatchMode.double && widget.conversationId != null) {
        final uri = Uri.parse('https://settee.jp/conversations/${widget.conversationId}/messages/');
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final list = json.decode(utf8.decode(res.bodyBytes)) as List<dynamic>;
          setState(() => messages = list);
          _warmAvatarCacheFromMessages(list);
        }
      } else {
        final uri = Uri.parse('https://settee.jp/messages/${widget.currentUserId}/${widget.matchedUserId}/');
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final list = json.decode(utf8.decode(res.bodyBytes)) as List<dynamic>;
          setState(() => messages = list);
          _warmAvatarCacheFromMessages(list);
        }
      }
    } catch (e) {
      debugPrint('メッセージ取得エラー: $e');
    }
  }

  Future<void> sendMessage(String text) async {
    try {
      if (widget.headerMode == MatchMode.double && widget.conversationId != null) {
        // Double: /conversations/<id>/messages/send/
        final uri = Uri.parse('https://settee.jp/conversations/${widget.conversationId}/messages/send/');
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'sender': widget.currentUserId, 'text': text}),
        );
        if (res.statusCode == 201) {
          _controller.clear();
          fetchMessages();
        } else {
          debugPrint('送信失敗(double): ${res.statusCode} ${res.body}');
        }
      } else {
        // Single: /messages/send/
        final uri = Uri.parse('https://settee.jp/messages/send/');
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'sender': widget.currentUserId,
            'receiver': widget.matchedUserId,
            'text': text,
          }),
        );
        if (res.statusCode == 201) {
          _controller.clear();
          fetchMessages();
        } else {
          debugPrint('送信失敗(single): ${res.statusCode} ${res.body}');
        }
      }
    } catch (e) {
      debugPrint('送信エラー: $e');
    }
  }

  // ---- 招待（/double-match/invite/ に合わせ済み）
  Future<bool> _inviteToConversation(String inviteeUserId) async {
    final cid = widget.conversationId;
    if (cid == null) {
      debugPrint('[invite] no conversationId');
      return false;
    }
    final uri = Uri.parse('https://settee.jp/double-match/invite/');
    final bodyMap = {
      'conversation_id': cid,
      'inviter': widget.currentUserId.trim(),
      'invitee': inviteeUserId.trim(),
    };
    try {
      final body = jsonEncode(bodyMap);
      debugPrint('[invite] POST $uri body=$body');
      final res = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
      debugPrint('[invite] status=${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) return true;

      String msg = '招待に失敗しました (${res.statusCode})';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] is String) msg = m['error'];
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      return false;
    } catch (e) {
      debugPrint('[invite] error=$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ネットワークエラーで招待に失敗しました')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final self = MatchUser(
      userId: widget.currentUserId,
      avatarUrl: _avatarCache[widget.currentUserId],
      displayName: 'あなた',
    );
    final partner = MatchUser(
      userId: widget.matchedUserId,
      avatarUrl: _avatarCache[widget.matchedUserId],
      displayName: widget.matchedUserNickname,
    );

    // 本文はスクロール全体で管理（ヘッダー＋メッセージ一覧）。
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.matchedUserNickname),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // スクロール領域：ヘッダー（幅Max/比率厳守）+ メッセージ（リスト）
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ヘッダー：横幅いっぱい・高さ=幅/比率（→ 横余白ゼロ）
                SliverToBoxAdapter(
                  child: MatchBanner(
                    mode: widget.headerMode,
                    self: self,
                    partner: partner,
                    myInvitee: null,            // 必要ならサーバから取得
                    partnerInvitee: null,       // 必要ならサーバから取得
                    onInvite: (widget.headerMode == MatchMode.double && widget.conversationId != null)
                        ? _inviteToConversation
                        : null,
                  ),
                ),

                // メッセージ一覧（下に向かって古→新の順。上にスクロールで過去を見る一般的なUI）
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList.separated(
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final senderId = '${message['sender']}';
                      final isMe = senderId == widget.currentUserId;
                      final text = (message['text'] ?? '').toString();

                      // 小さめの丸アイコン（左側に表示）
                      Widget smallAvatar(String? url) => Container(
                        width: 26, height: 26,
                        margin: const EdgeInsets.only(right: 6), // バブルとの間隔
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF444444)),
                        clipBehavior: Clip.antiAlias,
                        child: (url == null || url.isEmpty)
                            ? const Icon(Icons.person, color: Colors.white70, size: 16)
                            : Image.network(url, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white70, size: 16)),
                      );

                      // バブル（最大幅=画面の50% → 画面中央で折り返しやすい）
                      final maxW = MediaQuery.of(context).size.width * 0.50;
                      final bubble = Container(
                        constraints: BoxConstraints(maxWidth: maxW),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueAccent : Colors.grey[300],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          text,
                          softWrap: true,
                          style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 15),
                        ),
                      );

                      // 行：左にアイコン→バブル（自分の発言はバブルのみ、右寄せ）
                      return Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end, // ← バブルとアイコンの下辺を揃える
                        children: [
                          if (!isMe) smallAvatar(_avatarCache[senderId]),
                          bubble,
                        ],
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),

          // 入力欄（スクロール外に固定）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力',
                      hintStyle: TextStyle(color: Colors.white60),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isNotEmpty) sendMessage(t);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) sendMessage(text);
                  },
                ),
              ],
            ),
          ),
        ],
      ),

      // 既存のボトムバー
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.currentUserId),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context, String userId) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileBrowseScreen(currentUserId: userId)));
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.home_outlined, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => DiscoveryScreen(userId: userId)));
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.search, color: Colors.black),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 10.0),
            child: Image(image: AssetImage('assets/logo_text.png'), width: 70),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 10.0),
            child: Icon(Icons.mail, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.person_outline, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
