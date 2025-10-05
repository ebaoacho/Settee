import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' as ui;

enum MatchMode { single, double }

class MatchUser {
  final String userId;
  final String? avatarUrl;
  final String? displayName;
  const MatchUser({required this.userId, this.avatarUrl, this.displayName});
}

class MatchCelebrationScreen extends StatefulWidget {
  final MatchMode mode;
  final MatchUser self;             // 自分
  final MatchUser partner;          // 直接マッチした相手
  final MatchUser? myInvitee;       // 自分が招待した人（任意）
  final MatchUser? partnerInvitee;  // 相手が招待した人（任意）
  final Future<bool> Function(String inviteeUserId)? onInvite;
  final VoidCallback? onStartChat;

  const MatchCelebrationScreen({
    super.key,
    required this.mode,
    required this.self,
    required this.partner,
    this.myInvitee,
    this.partnerInvitee,
    this.onInvite,
    this.onStartChat,
  });

  @override
  State<MatchCelebrationScreen> createState() => _MatchCelebrationScreenState();
}

class _MatchCelebrationScreenState extends State<MatchCelebrationScreen> {
  double? _bgAspect; // 背景画像の縦横比（width/height）
  late MatchUser? _myInvitee;
  late MatchUser? _partnerInvitee;
  bool _inviting = false;

  // ====== 配置パラメータ（画像に対する相対座標/サイズ） ======
  // 0.0〜1.0 の座標（背景画像の左上=0,0／右下=1,1）
  // 直感的に調整できるようマップに分離しています。
  static const _doublePositions = <String, Offset>{
    // DoubleMatch.png：
    // 左上=相手、右上=相手が招待、左下=自分、右下=自分が招待
    'partner'        : Offset(0.26, 0.37),
    'partnerFriend'  : Offset(0.74, 0.37),
    'self'           : Offset(0.26, 0.74),
    'myFriend'       : Offset(0.74, 0.74),
  };
  static const _doubleAvatarDiameterFrac = 0.26; // 直径=画面幅*この比率

  static const _singlePositions = <String, Offset>{
    // SingleMatch.png：
    // 左=自分、右=相手、右上=相手が招待、右下=自分が招待
    'self'           : Offset(0.30, 0.58),
    'partner'        : Offset(0.70, 0.58),
    'partnerFriend'  : Offset(0.80, 0.33),
    'myFriend'       : Offset(0.80, 0.82),
  };
  static const _singleAvatarDiameterFracMain = 0.30;
  static const _singleAvatarDiameterFracInvite = 0.20;

  @override
  void initState() {
    super.initState();
    _myInvitee = widget.myInvitee;
    _partnerInvitee = widget.partnerInvitee;
    _loadBackgroundAspect();
  }

  Future<void> _loadBackgroundAspect() async {
    final asset = widget.mode == MatchMode.double
        ? 'assets/DoubleMatch.png'
        : 'assets/SingleMatch.png';

    final imgData = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(imgData.buffer.asUint8List());
    final fi = await codec.getNextFrame();
    final w = fi.image.width.toDouble();
    final h = fi.image.height.toDouble();
    if (mounted) setState(() => _bgAspect = w / h);
  }

  bool get _readyForChat {
    // どちらのレイアウトでも「両者が1人ずつ招待している」ことをチャット開始条件に
    return _myInvitee != null && _partnerInvitee != null;
  }

  Future<void> _openInviteDialog() async {
    if (widget.onInvite == null) return;
    final controller = TextEditingController();

    final inviteeId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('招待する'),
            ),
          ],
        );
      },
    );

    if (inviteeId == null || inviteeId.isEmpty) return;

    setState(() => _inviting = true);
    final ok = await widget.onInvite!(inviteeId).catchError((_) => false);
    setState(() => _inviting = false);

    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('招待に失敗しました')),
      );
      return;
    }

    // 成功時：最低限の UI 反映（サーバからの実ユーザ情報に置き換えるのが理想）
    setState(() {
      _myInvitee = MatchUser(userId: inviteeId, avatarUrl: null, displayName: 'Friend');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgAsset = widget.mode == MatchMode.double
        ? 'assets/DoubleMatch.png'
        : 'assets/SingleMatch.png';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 白い余白を持つレターボックス
            LayoutBuilder(
              builder: (context, c) {
                final ratio = _bgAspect ?? (9 / 16); // 読み込み前は暫定
                final maxW  = c.maxWidth;
                final maxH  = c.maxHeight;

                // 画面内に収まる最大サイズ（アスペクト固定）
                double w = maxW;
                double h = w / ratio;
                if (h > maxH) {
                  h = maxH;
                  w = h * ratio;
                }

                return ColoredBox(
                  color: Colors.white, // 余白は白
                  child: Center(       // ← 縦方向も中央に
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // ちょうど w×h に敷くので fill でOK（containでも可）
                          Image.asset(bgAsset, fit: BoxFit.fill),
                          _buildAvatarsOverlay(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // 下部の操作エリア（チャット開始／招待ボタン／注意文）
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_readyForChat)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.near_me_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),

                        ],
                      ),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            onPressed: _inviting ? null : _openInviteDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(_inviting ? '招待中...' : '友だちを招待'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('閉じる', style: TextStyle(color: Colors.white70)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== アバターのオーバーレイ ======
  Widget _buildAvatarsOverlay() {
    switch (widget.mode) {
      case MatchMode.double:
        return _DoubleOverlay(
          self: widget.self,
          partner: widget.partner,
          myInvitee: _myInvitee,
          partnerInvitee: _partnerInvitee,
        );
      case MatchMode.single:
        return _SingleOverlay(
          self: widget.self,
          partner: widget.partner,
          myInvitee: _myInvitee,
          partnerInvitee: _partnerInvitee,
        );
    }
  }
}

// ---- DoubleMatch の配置 ----
class _DoubleOverlay extends StatelessWidget {
  final MatchUser self, partner;
  final MatchUser? myInvitee, partnerInvitee;

  const _DoubleOverlay({
    required this.self,
    required this.partner,
    required this.myInvitee,
    required this.partnerInvitee,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final d = c.maxWidth * _MatchCelebrationScreenState._doubleAvatarDiameterFrac;

      return Stack(children: [
        _avatarAt(self,        _MatchCelebrationScreenState._doublePositions['self']!,        d),
        _avatarAt(partner,     _MatchCelebrationScreenState._doublePositions['partner']!,     d),
        if (partnerInvitee != null)
          _avatarAt(partnerInvitee!, _MatchCelebrationScreenState._doublePositions['partnerFriend']!, d),
        if (myInvitee != null)
          _avatarAt(myInvitee!,      _MatchCelebrationScreenState._doublePositions['myFriend']!,      d),
      ]);
    });
  }

  Widget _avatarAt(MatchUser u, Offset frac, double diameter) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(-1 + 2 * frac.dx, -1 + 2 * frac.dy),
        child: _AvatarCircle(url: u.avatarUrl, size: diameter),
      ),
    );
  }
}

// ---- SingleMatch の配置 ----
class _SingleOverlay extends StatelessWidget {
  final MatchUser self, partner;
  final MatchUser? myInvitee, partnerInvitee;

  const _SingleOverlay({
    required this.self,
    required this.partner,
    required this.myInvitee,
    required this.partnerInvitee,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final dMain   = c.maxWidth * _MatchCelebrationScreenState._singleAvatarDiameterFracMain;
      final dInvite = c.maxWidth * _MatchCelebrationScreenState._singleAvatarDiameterFracInvite;

      return Stack(children: [
        _avatarAt(self,    _MatchCelebrationScreenState._singlePositions['self']!,    dMain),
        _avatarAt(partner, _MatchCelebrationScreenState._singlePositions['partner']!, dMain),
        if (partnerInvitee != null)
          _avatarAt(partnerInvitee!, _MatchCelebrationScreenState._singlePositions['partnerFriend']!, dInvite),
        if (myInvitee != null)
          _avatarAt(myInvitee!,      _MatchCelebrationScreenState._singlePositions['myFriend']!,      dInvite),
      ]);
    });
  }

  Widget _avatarAt(MatchUser u, Offset frac, double diameter) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(-1 + 2 * frac.dx, -1 + 2 * frac.dy),
        child: _AvatarCircle(url: u.avatarUrl, size: diameter),
      ),
    );
  }
}

// 円形アバター（白フチ＋軽い影）
class _AvatarCircle extends StatelessWidget {
  final String? url;
  final double size;
  const _AvatarCircle({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final child = (url != null && url!.isNotEmpty)
        ? ClipOval(child: Image.network(url!, width: size, height: size, fit: BoxFit.cover))
        : Container(
            width: size, height: size,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF444444)),
            child: const Icon(Icons.person, color: Colors.white70),
          );

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.03),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipOval(child: child),
    );
  }
}
