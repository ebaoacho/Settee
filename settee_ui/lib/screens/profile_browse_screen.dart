import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'user_profile_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'area_selection_screen.dart';
import 'search_filter_screen.dart';
import 'point_exchange_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'paywall_screen.dart';
import 'chat_screen.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

enum LikeKind { superLike, messageLike, treatLike }

// バナー画像のパス（必要に応じてファイル名を合わせてください）
const Map<LikeKind, String> kLikeBannerAsset = {
  LikeKind.superLike   : 'assets/superlike_banner.png',   // 水色系
  LikeKind.messageLike : 'assets/messagelike_banner.png', // オレンジ系
  LikeKind.treatLike   : 'assets/treatlike_banner.png',   // 黄色系
};

// ぼかしの色（演出の下半分に使う）
const Map<LikeKind, Color> kLikeTintColor = {
  LikeKind.superLike   : Color(0xFF2EB7FF), // 水色
  LikeKind.messageLike : Color(0xFFFF8A00), // オレンジ
  LikeKind.treatLike   : Color(0xFFFFC400), // 黄色
};

class ProfileBrowseScreen extends StatefulWidget {
  final String currentUserId;
  final bool showTutorial;

  const ProfileBrowseScreen({super.key, required this.currentUserId, this.showTutorial = false});

  @override
  State<ProfileBrowseScreen> createState() => _ProfileBrowseScreenState();
}

class _ProfileBrowseScreenState extends State<ProfileBrowseScreen> {
  List<Map<String, dynamic>> profiles = [];
  Map<String, Map<int, String>> userImageUrls = {};
  Map<String, int> imageIndexes = {};
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> _unreadMatches = [];
  bool isFetching = false;
  bool isLoading = true;
  bool? isMatchMultiple;
  int currentPageIndex = 0;
  List<DateTime> availableDates = [];
  SearchFilters? _filters;
  final _spotlight = _SpotlightRegistry();
  bool _requiresKyc = true;
  bool _hasSeenTutorial = false;
  bool _didRequestCameraOnce = false;
  bool _showEmptyState = false;
  int _listGeneration = 0;
  int _msgLikeCredits = 0;
  int _superLikeCredits = 0;
  DateTime? _setteePlusUntil;
  DateTime? _setteeVipUntil;
  bool _refineUnlocked = false;
  bool _setteePlusActive = false;
  bool _setteeVipActive = false;
  bool _boostActive = false;
  bool _privateActive = false;
  bool _kycOpening = false;
  bool _kycSubmitted = false;
  bool get _isPagingLocked => _isLikeEffectActive;

  int _treatLikeCredits = 0;
  bool _backtrackEnabled = false;
  bool get _canMessageLike => _msgLikeCredits > 0;
  bool get _canSuperLike   => _superLikeCredits > 0;
  bool get _canTreatLike   => _treatLikeCredits > 0;
  bool get _canRefine => _refineUnlocked;

  LikeKind? _activeLikeEffect;
  Timer? _likeEffectTimer;

  
  bool get _isPageViewReady =>
    mounted && !isLoading && profiles.isNotEmpty && _pageController.hasClients;

  /// PageView が“ツリーに戻ってから” 1ページ目へ移動
  void _jumpToFirstPageSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isPageViewReady) {
        try {
          _pageController.jumpToPage(0);
        } catch (_) {
          // フレーム競合の保険（何もしない）
        }
      }
    });
  }
  
  // 0-width/ZWJ を除去して user_id を正規化
  String _normId(String? s) =>
      (s ?? '').replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

  bool _didBootstrap = false;

  // 失敗/タイムアウトしても先へ進める軽量ラッパ
  Future<void> _swallow(Future<void> fut, {String tag = '' , Duration? timeout}) async {
    try {
      if (timeout != null) {
        await fut.timeout(timeout);
      } else {
        await fut;
      }
    } catch (e) {
      debugPrint('[bootstrap:$tag] $e'); // 失敗はログだけ
    }
  }

  @override
  void initState() {
    super.initState();

    // チュートリアルはそのまま
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _showTutorialDialog();
        if (!mounted) return;
        _onTutorialFinished();
      });
    }

    // PageView 末尾付近での追加フェッチ
    _pageController.addListener(() {
      if (!_pageController.hasClients) return;
      final pg = _pageController.page;
      if (pg != null && pg.round() >= profiles.length - 3) {
        _fetchProfiles();
      }
    });

    // ツリーに載ってからブート
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrap();
      _checkAndShowUnreadMatchesDialog();
    });
  }

  Future<void> _checkAndShowUnreadMatchesDialog() async {
    if (!mounted) return;

    try {
      final uri = Uri.parse(
        'https://settee.jp/unread-matches/${widget.currentUserId}/',
      );
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final unreadCount = j['unread_count'] as int? ?? 0;
        final matches = j['matches'] as List<dynamic>;
        var partnerIds = <String>[];
        for (final match in matches) {
          partnerIds.add(match['partner']['user_id'] as String);
        }
        

        if (unreadCount > 0 && mounted) {
          _showUnreadMatchesDialog(context, unreadCount, partnerIds);
        }
      }
    } catch (e) {
      debugPrint('未読マッチチェックエラー: $e');
    }
  }


  Future<bool?> showModernMatchDialog(BuildContext context, int unreadCount) {
      return showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'match_notification',
        barrierColor: Colors.black.withOpacity(0.45),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        transitionBuilder: (ctx, anim, __, ___) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Opacity(
              opacity: curved.value,
              child: Center(
                child: Transform.scale(
                  scale: 0.92 + 0.08 * curved.value,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: MediaQuery.of(ctx).size.width * 0.86,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 26,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // アイコンバッジ
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF6B9D), Color(0xFFFF1744)],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55FF1744),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '新しいマッチ！',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$unreadCount件の新しいマッチがあります。\n今すぐチェックしてみましょう！',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.28),
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('後で'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF1744),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    shadowColor: const Color(0x66FF1744),
                                    elevation: 6,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('確認する'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

  void _showUnreadMatchesDialog(BuildContext context, int unreadCount, List<String> partnerIds) async {
    final result = await showModernMatchDialog(context, unreadCount);

    // mounted チェックを追加してBuildContextの安全性を確保
    if (result == true && mounted) {
      // 確認するボタンが押された場合
      if (!mounted) return;

      // TODO: N+1問題解消
      for (final partnerId in partnerIds) {
        final url = 'https://settee.jp/match/${widget.currentUserId}/$partnerId/read/';
        debugPrint('既読更新URL: $url');
        
        final updateResponse = await http.patch(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
        );

        if (updateResponse.statusCode == 200) {
          debugPrint('既読にしました');
        } else {
          debugPrint('既読更新失敗: ${updateResponse.statusCode}');
          debugPrint('レスポンスボディ: ${updateResponse.body}');
        }
      }

      // マッチ一覧画面に遷移
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MatchedUsersScreen(userId: widget.currentUserId),
        ),
      );
    }

    // TODO: N+1問題解消
    for (final partnerId in partnerIds) {
      final url =
          'https://settee.jp/match/${widget.currentUserId}/$partnerId/read/';
      debugPrint('既読更新URL: $url');

      final updateResponse = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      if (updateResponse.statusCode == 200) {
        debugPrint('既読にしました');
      } else {
        debugPrint('既読更新失敗: ${updateResponse.statusCode}');
        debugPrint('レスポンスボディ: ${updateResponse.body}');
      }
    }
    // result == false または null の場合は何もしない（ダイアログを閉じるだけ）
  }

  Future<void> _bootstrap() async {
    if (_didBootstrap) return;
    _didBootstrap = true;

    if (mounted && !isLoading) setState(() => isLoading = true);

    // ✅ ここは “含めない”：投げっぱなしで起動（await しない）
    _fetchCurrentUserMatchMode();

    // 初期APIは Future.wait にまとめる（← match mode は除外）
    await Future.wait<void>([
      _swallow(_loadReceivedLikesOnce(),       tag: 'likes',    timeout: const Duration(seconds: 8)),
      _swallow(_fetchProfiles(),               tag: 'profiles', timeout: const Duration(seconds: 10)),
      _swallow(_fetchEntitlements(widget.currentUserId), tag: 'ent', timeout: const Duration(seconds: 8)),
      _swallow(_fetchAvailableDates(),         tag: 'dates',    timeout: const Duration(seconds: 6)),
    ]);

    if (!mounted) return;

    setState(() => isLoading = false);

    // 初回表示ユーザに対して有料Like演出をチェック
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || profiles.isEmpty) return;
      final firstId = _normId(profiles[0]['user_id']?.toString());
      _checkIncomingPaidLikeFor(firstId);
    });
  }

  Future<int?> _startDoubleMatchConversation(String otherUserId) async {
    final uri = Uri.parse('https://settee.jp/double-match/start/');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_a': widget.currentUserId, 'user_b': otherUserId}),
    );
    if (r.statusCode >= 400) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['id'] as num?)?.toInt();
  }

  Future<void> _createMatchAndMarkRead(String me, String other) async {
    try {
      // 1. マッチを作成
      final matchResponse = await http.post(
        Uri.parse('https://settee.jp/match/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'me': me,
          'other': other,
        }),
      );
      debugPrint('matchResponse: ${matchResponse.body}');
      
      if (matchResponse.statusCode == 201) {
        debugPrint('マッチ作成成功');
         
        // 2. 必要であれば既読にする
        final updateResponse = await http.patch(
          Uri.parse('https://settee.jp/match/$me/$other/read/'),
          headers: {
            'Content-Type': 'application/json',
          },
        );
        
        if (updateResponse.statusCode == 200) {
          debugPrint('既読にしました');
        } else {
          debugPrint('既読更新失敗: ${updateResponse.statusCode}');
        }
        
      } else if (matchResponse.statusCode == 400) {
        final error = jsonDecode(matchResponse.body);
        debugPrint('マッチ作成失敗: ${error['error']}');
      } else {
        debugPrint('マッチ作成失敗: ${matchResponse.statusCode}');
      }
      
    } catch (e) {
      debugPrint('エラー: $e');
    }
  }

  Future<void> _addSetteePoints(String userId, int amount ) async {
    final uri = Uri.parse('https://settee.jp/add_settee_points/');
    final r = await http.post(
      uri, 
      headers: {
        'Content-Type': 'application/json'
      },
      body: jsonEncode(
        {'user_id': userId, 'amount': amount}
      ));
    if (r.statusCode == 200) {
      debugPrint('ポイントが作成されました');
    } else {
      debugPrint('ポイント作成失敗: ${r.statusCode}');
      debugPrint('レスポンスボディ: ${r.body}');
    }
  }

  /// like送信後、「相互Likeになったか」を確認してマッチ演出を表示
  Future<void> _checkAndShowMatch(String otherUserId) async {
    // ---- 追加: ログ & ID正規化 & 二重起動ガード ----
    String _normId(String? s) =>
        (s ?? '').replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
    void _m(String m) => debugPrint('[match] $m');

    final me = _normId(widget.currentUserId);
    final other = _normId(otherUserId);

    // 同一ユーザに対して何度もマッチ画面が開かないように
    _openedMatchFor ??= <String>{};
    if (_openedMatchFor!.contains(other)) {
      _m('skip: already opened for=$other');
      return;
    }

    try {
      // 1) サーバで相互Like確認（ついでにニックネームも拾う）
      final uri = Uri.parse('https://settee.jp/matched-users/$me/');
      _m('GET $uri');
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      _m('matched-users status=${r.statusCode}');
      if (r.statusCode != 200 || !mounted) return;

      await _createMatchAndMarkRead(me, other);
      await _addSetteePoints(me, 5);
      await _addSetteePoints(other, 5);

      final List list = jsonDecode(r.body) as List;
      final Map<String, dynamic>? partnerEntry = list.cast<Map<String, dynamic>?>()
        .firstWhere((e) => _normId(e?['user_id']?.toString()) == other, orElse: () => null);

      final bool matched = partnerEntry != null;
      _m('matched=$matched for other=$other');
      if (!matched || !mounted) return;

      final partnerNickname = (partnerEntry?['nickname']?.toString() ?? other).trim();

      // 2) 会話を準備（DOUBLE を再利用して convId を取得：失敗は null 許容）
      int? convId;
      try {
        convId = await _startDoubleMatchConversation(other);
        _m('convId=$convId');
      } catch (e) {
        _m('startDoubleMatch error=$e');
      }

      // 3) 遷移先：ChatScreen（ヘッダーにマッチ画像＋相対アバター）
      //    - conversationId を渡すと招待ボタンが出ます
      //    - headerMode は isMatchMultiple に合わせて Single/Double
      final headerMode = (isMatchMultiple ?? true) ? MatchMode.double : MatchMode.single;

      _openedMatchFor!.add(other); // 重複起動ガードON
      _m('push ChatScreen with headerMode=$headerMode convId=$convId');

      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => ChatScreen(
          currentUserId: me,
          matchedUserId: other,
          matchedUserNickname: partnerNickname,
          conversationId: convId,          // null なら招待ボタンは非表示
          headerMode: headerMode,          // ← 先ほどのバナーと同じ配置ルールを使用
        ),
      ));
      
      // マッチ画面から戻った後に未読マッチを更新
      if (mounted) {
        await _checkAndShowUnreadMatchesDialog();
      }
    } catch (e) {
      debugPrint('match-check failed: $e');
    }
  }

// 画面重複表示を防ぐための小さなセット（Stateのフィールドとして宣言して下さい）
Set<String>? _openedMatchFor;


  Future<String> _fetchEntitlements(String userId) async {
    final uri = Uri.parse('https://settee.jp/users/$userId/entitlements/');
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return 'free';

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return 'free';

      final now = DateTime.now();

      // ---- VIPの有効判定（activeフラグ or untilでフォールバック）----
      final sVip = j['settee_vip_until'] as String?;
      final vipUntil = sVip == null ? null : DateTime.tryParse(sVip);
      final vipActive = (j['settee_vip_active'] ?? false) as bool ||
          (vipUntil != null && vipUntil.isAfter(now));

      // ---- PLUSの有効判定（activeフラグ or untilでフォールバック）----
      final sPlus = j['settee_plus_until'] as String?;
      final plusUntil = sPlus == null ? null : DateTime.tryParse(sPlus);
      final plusActive = (j['settee_plus_active'] ?? false) as bool ||
          (plusUntil != null && plusUntil.isAfter(now));

      // ---- プラン文字列（vip優先）----
      final plan = vipActive ? 'vip' : (plusActive ? 'plus' : 'free');

      setState(() {
        // 残数系
        _msgLikeCredits   = (j['message_like_credits'] ?? 0) as int;
        _superLikeCredits = (j['super_like_credits']  ?? 0) as int;
        _treatLikeCredits = (j['treat_like_credits']  ?? 0) as int;

        // 期間/フラグ
        _refineUnlocked   = (j['refine_unlocked'] ?? j['can_refine'] ?? false) as bool;
        _setteePlusUntil  = plusUntil;
        _setteeVipUntil   = vipUntil;
        _setteePlusActive = plusActive;
        _setteeVipActive  = vipActive;
        _boostActive      = (j['boost_active']        ?? false) as bool;
        _privateActive    = (j['private_mode_active'] ?? false) as bool;

        // ✅ vipなら無条件でtrue（サーバがbacktrack_enabledを返してもvip優先）
        _backtrackEnabled = vipActive || ((j['backtrack_enabled'] ?? false) as bool);
      });

      return plan;
    } catch (_) {
      return 'free';
    }
  }

  // チュートリアルを表示するコードから呼ぶ用
  void _onTutorialFinished() async {
    _hasSeenTutorial = true;

    // ★ ここが肝：チュートリアルを閉じた“直後”に1回だけ request
    final s = await Permission.camera.status;
    if (!s.isGranted && !s.isRestricted) {
      await Permission.camera.request();
    }

    if (_requiresKyc) {
      // 既存のKYC開始
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startKycFlow();
      });
    }
  }

  // KYCフローを起動（フルスクリーンダイアログ）
  Future<void> _startKycFlow() async {
    if (_kycOpening || _kycSubmitted) return;  // ← 二重起動＆提出済みガード
    _kycOpening = true;
    try {
      final result = await Navigator.of(context).push<KycResult>(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => KycFlowScreen(userId: widget.currentUserId),
          transitionDuration: const Duration(milliseconds: 220),
          fullscreenDialog: true,
          opaque: true,
        ),
      );
      if (!mounted) return;
      if (result == KycResult.submitted) {
        setState(() => _kycSubmitted = true);  // 以後は開かない
        _showKycUploadedBanner();
      }
    } finally {
      _kycOpening = false;
    }
  }

  void _showKycUploadedBanner() {
    // 画面上部に緑のインフォメーションバー
    final controller = ScaffoldMessenger.of(context);
    controller.clearSnackBars();
    controller.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        backgroundColor: const Color(0xFF1FD27C), // 近いグリーン
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('画像をアップロードしました！',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            SizedBox(height: 2),
            Text('年齢確認完了までしばらくお待ちください',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _fetchCurrentUserMatchMode() async {
    final url = Uri.parse('https://settee.jp/user-profile/${widget.currentUserId}/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        isMatchMultiple = data['match_multiple'];
      });
    } else {
      debugPrint("ユーザー情報取得失敗: ${response.body}");
    }
  }

  Future<void> _showTutorialDialog() async {
    // 画像サイズの割合（ページごと）
    const List<double> _imgHeightFracByPage = <double>[0.70, 0.60, 0.70, 0.65, 0.50];
    const List<double> _imgWidthFracByPage  = <double>[0.80, 0.80, 0.80, 0.80, 0.80];

    // ── ハイライト対象の定義 ──
  final pages = <_GuidePage>[
    _GuidePage(
      title: 'ひとりマッチしよう',
      message: '好みのユーザーに\nライクしよう',
      arrow: BubbleArrowDirection.up,
      bubbleAlignment: Alignment.topCenter,
      edgePadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      arrowOffset: 0.75,
      imageAsset: 'assets/hitoride_match.png',
      highlightTarget: _TutorialTarget.soloMatch,
      highlightPadding: const EdgeInsets.all(10),
      highlightAsCircle: false,
    ),
    _GuidePage(
      title: '友だちと一緒に\nDobleマッチしよう',
      message: 'マッチした後に友だちを\nチャットに招待し\nDobleマッチをしよう',
      arrow: BubbleArrowDirection.up,
      bubbleAlignment: Alignment.topCenter,
      edgePadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      arrowOffset: 0.50,
      imageAsset: 'assets/minnnade_match.png',
      highlightTarget: _TutorialTarget.groupMatch,
      highlightPadding: const EdgeInsets.all(10),
      highlightAsCircle: false,
    ),
    _GuidePage(
      title: 'あなたがマッチしたい\nエリアを選ぼう',
      message: '同じエリアを選択している\nユーザーとマッチしよう',
      arrow: BubbleArrowDirection.up,
      bubbleAlignment: Alignment.topCenter,
      edgePadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      arrowOffset: 0.25,
      imageAsset: 'assets/area_choice.png',
      highlightTarget: _TutorialTarget.areaSelect,
      highlightPadding: const EdgeInsets.all(10),
      highlightAsCircle: false,
    ),
    _GuidePage(
      title: 'SetteeポイントをGetしよう',
      message: '貯まったポイントで\n機能解放をしよう',
      arrow: BubbleArrowDirection.up,
      bubbleAlignment: Alignment.topCenter,
      edgePadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      arrowOffset: 0.10,
      imageAsset: 'assets/logo.png',
      highlightTarget: _TutorialTarget.pointsBadge,
      highlightPadding: const EdgeInsets.all(8),
      highlightAsCircle: true,
    ),
    _GuidePage(
      title: 'あなたが遊べる予定を選んで\nマッチしよう！',
      message: '1週間のカレンダーであなたと\n同じ日にちが空いている\nユーザーを優先して表示しよう！',
      arrow: BubbleArrowDirection.up,
      bubbleAlignment: Alignment.topCenter,
      edgePadding: const EdgeInsets.only(top: 100, left: 24, right: 24),
      arrowOffset: 0.50,
      imageAsset: 'assets/logo.png',
      highlightTarget: _TutorialTarget.calendar,
      highlightPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      highlightAsCircle: false,
    ),
  ];

    int index = 0;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent, // ← 背景は自前オーバーレイで暗くする
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            void next() {
              if (index < pages.length - 1) {
                setState(() => index++);
              } else {
                Navigator.of(ctx).pop(); // ダイアログを閉じるだけ
                // 親ツリーの遷移は postFrame で（unmounted回避）
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _onTutorialFinished();
                });
              }
            }

            void skip() {
              Navigator.of(ctx).pop(); // スキップで閉じる
            }

            final page = pages[index];

            return SafeArea(
              child: Stack(
                children: [
                  // ───────── 半透明オーバーレイ（穴あき） ─────────
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _spotlight, // ← レイアウト取得完了で自動再描画
                      builder: (_, __) {
                        return _SpotlightOverlay(
                          registry: _spotlight,
                          target: page.highlightTarget,
                          padding: page.highlightPadding ?? EdgeInsets.zero,
                          asCircle: page.highlightAsCircle ?? false,
                          overlayOpacity: 0.55, // 半透明度
                          dimColor: Colors.black, // 暗転色
                        );
                      },
                    ),
                  ),

                  // ───────── 吹き出し本体 ─────────
                  Align(
                    alignment: page.bubbleAlignment,
                    child: Padding(
                      padding: page.edgePadding,
                      child: _SpeechBubble(
                        maxHeightFraction: 0.60,
                        direction: page.arrow,
                        arrowOffset: page.arrowOffset,
                        arrowInset: page.arrowInset,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: LayoutBuilder(
                            builder: (context, bubble) {
                              final double bubbleH = bubble.maxHeight.isFinite
                                  ? bubble.maxHeight
                                  : MediaQuery.of(context).size.height * 0.60;

                              final double imgHFrac = _imgHeightFracByPage[index];
                              final double imgWFrac = _imgWidthFracByPage[index];
                              final double imgBoxH  = bubbleH * imgHFrac;

                              return Column(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    page.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  if (page.imageAsset != null)
                                    SizedBox(
                                      height: imgBoxH,
                                      child: Center(
                                        child: FractionallySizedBox(
                                          widthFactor: imgWFrac,
                                          child: FittedBox(
                                            fit: BoxFit.contain,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.asset(page.imageAsset!),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 8),

                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      page.message,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        height: 1.3,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ───────── 進捗ドット＋ボタン ─────────
                  Positioned(
                    left: 24,
                    right: 24,
                    // ← ここを差し替え
                    bottom: _tutorialControlsBottom(context),
                    child: SafeArea(
                      // ここは下端の被りを避けるための最低余白。上へ寄せたいので 0 に近づけます
                      minimum: const EdgeInsets.only(bottom: 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Dots(current: index, length: pages.length, activeSize: 8, inactiveSize: 8),
                          const SizedBox(height: 2), // 少しだけ詰める（4→2）
                          SizedBox(
                            height: 46, // 48→46でわずかに詰める
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: skip,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.white70),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('今すぐスタート',
                                        style: TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: next,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      index == pages.length - 1 ? 'はじめる' : '次へ',
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double _tutorialControlsBottom(BuildContext context) {
    final view = MediaQuery.of(context);
    // 端末下部のセーフエリア（ホームインジケータ等）
    final safe = view.padding.bottom;

    const desiredLift = 64.0;

    // 最低限の下端マージン（0〜8px くらい推奨）
    const minBottomMargin = 4.0;

    final bottom = (safe + minBottomMargin + desiredLift).clamp(16.0, 120.0);

    return bottom;
  }

  Future<void> _fetchProfiles() async {
    if (isFetching) return;
    final int gen = _listGeneration;

    setState(() => isFetching = true);

    try {
      final f = _filters;
      final qp = <String, String>{
        'offset': '${profiles.length}',
        'limit': '2',
      };
      if (f?.gender != null)     qp['gender']       = f!.gender!;
      if (f?.ageMin != null)     qp['age_min']      = '${f!.ageMin}';
      if (f?.ageMax != null)     qp['age_max']      = '${f!.ageMax}';
      if (f?.heightMin != null)  qp['height_min']   = '${f!.heightMin}';
      if (f?.heightMax != null)  qp['height_max']   = '${f!.heightMax}';
      if (f?.occupation != null) qp['occupation']   = f!.occupation!;
      if (f?.mbtis != null && f!.mbtis!.isNotEmpty) {
        qp['mbti'] = f.mbtis!.join(',');
        if (f.includeNullMbti == true) qp['mbti_include_null'] = '1';
      }

      final uri = Uri(
        scheme: 'https',
        host: 'settee.jp',
        path: '/recommended-users/${widget.currentUserId}/',
        queryParameters: qp,
      );

      // タイムアウトは任意
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      // ★ レスポンスが返った時点で世代が変わっていたら何もしないで終了
      if (!mounted || gen != _listGeneration) return;

      if (response.statusCode == 200) {
        final List<dynamic> raw = json.decode(response.body);
        final List<Map<String, dynamic>> newProfiles = raw.cast<Map<String, dynamic>>();

        // 念のためのクライアント側フィルタ
        final filtered = newProfiles.where(_matchesProfile).toList();

        setState(() {
          profiles.addAll(filtered);
        });

        for (final profile in filtered) {
          // ★ 現行世代を渡す
          _prefetchUserImages(profile['user_id'], gen: gen);
        }
      } else {
        return;
      }
    } catch (e) {
      debugPrint('fetch error: $e');
    } finally {
      // ★ 古い呼び出しが isFetching を false に戻さないように
      if (mounted && gen == _listGeneration) {
        setState(() => isFetching = false);
      }
    }
  }

  Future<void> _prefetchUserImages(String userId, {required int gen}) async {
    if (!mounted || gen != _listGeneration) return;

    const maxIndex = 9;
    const extensions = ['jpg', 'jpeg', 'png', 'heic', 'heif'];

    // 初期化は setState で（null → 空Map）
    setState(() {
      userImageUrls[userId] = <int, String>{};
    });

    for (int i = 1; i <= maxIndex; i++) {
      for (final ext in extensions) {
        if (!mounted || gen != _listGeneration) return;

        final url = 'https://settee.jp/images/$userId/${userId}_$i.$ext';
        try {
          final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
          if (!mounted || gen != _listGeneration) return;

          if (resp.statusCode == 200) {
            final map = userImageUrls[userId];
            if (map == null) return;        // 途中で clear 済みなら終了
            map[i] = url;

            try {
              if (mounted && gen == _listGeneration) {
                await precacheImage(NetworkImage(url), context);
              }
            } catch (_) {
              // 画面離脱中に走った場合は握りつぶす
            }

            if (mounted && gen == _listGeneration) {
              setState(() {});               // 進捗反映
            }
            break;                            // 次の i へ
          }
        } catch (_) {
          // タイムアウトなどは無視して次へ
        }
      }
    }
  }

  Widget _buildProfileImage(String userId) {
    final map = userImageUrls[userId];

    if (map == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (map.isEmpty) {
      return const Center(child: Text('画像がありません', style: TextStyle(color: Colors.white)));
    }

    // キーを昇順で並べて安定した順序に
    final keys = map.keys.toList()..sort();
    final urls = [for (final k in keys) map[k]!];

    // 現在のインデックスを安全に取得・補正
    final current = (imageIndexes[userId] ?? 0).clamp(0, urls.length - 1);
    imageIndexes[userId] = current;

    return GestureDetector(
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        final dx = details.localPosition.dx;
        setState(() {
          final now = imageIndexes[userId] ?? 0;
          if (dx < width / 2) {
            imageIndexes[userId] = (now - 1).clamp(0, urls.length - 1);
          } else {
            imageIndexes[userId] = (now + 1).clamp(0, urls.length - 1);
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            urls[imageIndexes[userId] ?? 0],
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Center(child: Text('画像を読み込めません', style: TextStyle(color: Colors.white))),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == (imageIndexes[userId] ?? 0) ? Colors.black : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Like送信：ここでは“絶対に”ページを進めない
  Future<void> _sendLike(String receiverId, int likeType, {String? message}) async {
    final url = Uri.parse('https://settee.jp/like/');
    final payload = <String, dynamic>{
      'sender': widget.currentUserId,
      'receiver': receiverId,
      'like_type': likeType,
    };
    if (likeType == 3 && message != null && message.trim().isNotEmpty) {
      payload['message'] = message.trim();
    }

    try {
      final r = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      // 必要ならエラーハンドリング（例: 400でSnackBar等）
      if (r.statusCode >= 400) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final msg = j['error']?.toString() ?? '送信に失敗しました';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('通信エラー: $e')));
      }
    }
  }

  // ✅ メッセージ入力用ボトムシート（ローカルControllerを使い、閉じた“後”でdispose）
  Future<String?> _openMessageLikeSheet() async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _MessageLikeSheet(), // ← 子に任せる
    );
    if (res == null) return null;
    final t = res.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _fetchAvailableDates() async {
    final url = Uri.parse(
        'https://settee.jp/user-profile/${widget.currentUserId}/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        availableDates = List<String>.from(data['available_dates'])
            .map((date) => DateTime.parse(date))
            .toList();
      });
    }
  }

  Widget _buildCalendar() {
    final today = DateTime.now().toUtc().add(const Duration(hours: 9));

    final List<DateTime> weekDates = List.generate(7, (i) => today.add(Duration(days: i)))
      ..add(DateTime(9999)); // ALLボタン用

    final List<String> weekDayLabels = weekDates.map((date) {
      if (date.year == 9999) return 'ALL';
      if (date.day == today.day && date.month == today.month && date.year == today.year) {
        return '今日';
      }
      const weekDays = ['月', '火', '水', '木', '金', '土', '日'];
      return weekDays[date.weekday - 1];
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _SpotlightTargetCapture(
        registry: _spotlight,
        target: _TutorialTarget.calendar,
        // Wrap 全体を“領域”としてハイライト
        child: Wrap(
          spacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(weekDates.length, (index) {
            final date = weekDates[index];
            final bool isAllButton = (date.year == 9999);
            final bool isTodayLabel = (weekDayLabels[index] == '今日');
            final bool isSelected = isAllButton
                ? availableDates.length == 7
                : availableDates.any((d) =>
                    d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day);

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isAllButton) {
                    availableDates = List<DateTime>.generate(7, (i) => today.add(Duration(days: i)));
                  } else {
                    final normalizedDate = DateTime(date.year, date.month, date.day);
                    if (isSelected) {
                      availableDates.removeWhere((d) =>
                          d.year == normalizedDate.year &&
                          d.month == normalizedDate.month &&
                          d.day == normalizedDate.day);
                    } else {
                      availableDates.add(normalizedDate);
                    }
                  }
                  _updateAvailableDates();
                });
              },
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      weekDayLabels[index],
                      style: TextStyle(
                        fontSize: isAllButton || isTodayLabel ? 8 : 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (!isAllButton)
                    Container(
                      width: 36,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withOpacity(0.5) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${date.day}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> _updateAvailableDates() async {
    final url = Uri.parse(
        'https://settee.jp/user-profile/${widget.currentUserId}/update-available-dates/');
    final body = jsonEncode({
      'available_dates': availableDates
          .map((d) => d.toIso8601String().split('T')[0])
          .toList(),
    });
    await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '条件に合うユーザーが見つかりませんでした',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openSearchFilters,
              icon: const Icon(Icons.tune, color: Colors.white),
              label: const Text('条件を調整する', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearchFilters() async {
    final result = await Navigator.push<SearchFilters>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchFilterScreen(
          initial: _filters,
          // currentUserGender: _currentUserGender, // 必要なら
        ),
      ),
    );
    if (result == null) return;

    setState(() {
      _listGeneration++;
      _filters = result;
      profiles.clear();
      userImageUrls.clear();
      imageIndexes.clear();
      currentPageIndex = 0;
      isLoading = true;     // ← 一旦ローディングにして PageView を外す
      _showEmptyState = false;
    });

    await _fetchProfiles();

    if (!mounted) return;

    setState(() {
      isLoading = false;    // ← PageView を戻すのはここ
      _showEmptyState = profiles.isEmpty;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (profiles.isNotEmpty) {
        _checkIncomingPaidLikeFor(profiles[0]['user_id']);
      }
    });

    // PageView が“戻って”から移動させる
    _jumpToFirstPageSafely();
  }

  Future<void> _loadReceivedLikesOnce() async {
    if (_loadingReceivedLikes) return;
    _loadingReceivedLikes = true;
    try {
      final uri = Uri.parse('https://settee.jp/likes/received/${widget.currentUserId}/?paid_only=1');

      final res = await http.get(uri);

      // ★ デバッグ: ステータスと生ボディ
      debugPrint('[recvLikes] status=${res.statusCode}');
      if (res.statusCode != 200) {
        debugPrint('[recvLikes] body=${res.body}');
        return;
      }

      final List data = jsonDecode(res.body) as List;

      // ★ デバッグ: 受け取った件数と先頭3件
      debugPrint('[recvLikes] count=${data.length}');
      debugPrint('[recvLikes] head=${data.take(3).toList()}');

      final tmp = <String, _ReceivedLike>{};
      for (final raw in data) {
        final map = raw as Map<String, dynamic>;

        // sender_id 正規化
        final dynamic s = map['sender_id'] ?? map['sender'];
        final senderId = (s is Map ? (s['user_id'] ?? '') : s).toString().trim();

        final int type = (map['like_type'] ?? 0) as int;
        final String? msg = (map['message'] as String?)?.trim();
        tmp[senderId] = _ReceivedLike(senderId: senderId, type: type, message: msg);
      }

      setState(() {
        _receivedLikes
          ..clear()
          ..addAll(tmp);
      });

      // ★ デバッグ: マップのキー一覧（=送ってきたユーザID）
      debugPrint('[recvLikes] keys=${_receivedLikes.keys.toList()}');

      // ★ 初回レース対策: 現在表示中ユーザで再チェック
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || profiles.isEmpty) return;
        final idx = (_pageController.hasClients ? _pageController.page?.round() : 0) ?? 0;
        final safe = idx.clamp(0, profiles.length - 1);
        final viewed = profiles[safe]['user_id'].toString().trim();
        debugPrint('[recvLikes] recheck current view=$viewed');
        _checkIncomingPaidLikeFor(viewed);
      });
    } catch (e) {
      debugPrint('[recvLikes] error=$e');
    } finally {
      _loadingReceivedLikes = false;
    }
  }


  // void _showTicketRequiredSheet(String message) {
  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: const Color(0xFF141414),
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  //     ),
  //     builder: (_) {
  //       return Padding(
  //         padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Row(children: const [
  //               Icon(Icons.lock_rounded, color: Colors.white, size: 18),
  //               SizedBox(width: 8),
  //               Text('機能がロックされています', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
  //             ]),
  //             const SizedBox(height: 10),
  //             Text(message, style: const TextStyle(color: Colors.white70)),
  //             const SizedBox(height: 16),
  //             Row(
  //               children: [
  //                 Expanded(
  //                   child: OutlinedButton(
  //                     style: OutlinedButton.styleFrom(
  //                       foregroundColor: Colors.white,
  //                       side: const BorderSide(color: Colors.white24),
  //                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  //                       padding: const EdgeInsets.symmetric(vertical: 12),
  //                     ),
  //                     onPressed: () {
  //                       Navigator.pop(context);
  //                       // 利用可能チケット一覧へ
  //                       Navigator.push(context,
  //                         MaterialPageRoute(builder: (_) =>
  //                           AvailableTicketsScreen(userId: widget.currentUserId),
  //                         ),
  //                       ).then((_) => _fetchEntitlements(widget.currentUserId));
  //                     },
  //                     child: const Text('保有チケットを確認'),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: ElevatedButton(
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: const Color(0xFF9D9D9D),
  //                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  //                       padding: const EdgeInsets.symmetric(vertical: 12),
  //                     ),
  //                     onPressed: () {
  //                       Navigator.pop(context);
  //                       // 交換画面（PointExchangeScreen）へ
  //                       Navigator.push(context,
  //                         MaterialPageRoute(builder: (_) =>
  //                           PointExchangeScreen(userId: widget.currentUserId),
  //                         ),
  //                       ).then((_) => _fetchEntitlements(widget.currentUserId));
  //                     },
  //                     child: const Text('チケットを交換'),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //       );
  //     },
  //   );
  // }

  void goPaywall(
    BuildContext context, {
    required String userId,
    String currentTier = 'free',
    bool campaignActive = true,
    bool replace = false,
  }) {
    final page = PaywallScreen(
      userId: userId,
      currentTier: currentTier,
      campaignActive: campaignActive,
    );
    if (replace) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => page),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }


  bool _matchesProfile(Map<String, dynamic> p) {
    final f = _filters;
    if (f == null) return true;

    // 性別（完全一致、プロフィール側が空なら無視）
    if (f.gender != null) {
      final g = (p['gender'] ?? '').toString();
      if (g.isNotEmpty && g != f.gender) return false;
    }

    // 年齢（範囲：inclusive）※プロフィールに年齢が無ければスルー
    if (f.ageMin != null || f.ageMax != null) {
      final a = _toInt(p['age']);
      if (a != null) {
        if (f.ageMin != null && a < f.ageMin!) return false;
        if (f.ageMax != null && a > f.ageMax!) return false;
      }
    }

    // 職業（完全一致、プロフィール側が空なら無視）
    if (f.occupation != null) {
      final o = (p['occupation'] ?? '').toString();
      if (o.isNotEmpty && o != f.occupation) return false;
    }

    // 身長（範囲：inclusive, cm）※"175cm" でも 175 でもOK。プロフィールに身長が無ければスルー
    if (f.heightMin != null || f.heightMax != null) {
      final h = _toHeightCm(p['height']);
      if (h != null) {
        if (f.heightMin != null && h < f.heightMin!) return false;
        if (f.heightMax != null && h > f.heightMax!) return false;
      }
    }

    // MBTI（複数選択に対応）
    // SearchFilters.mbtis は Set<String>? を想定（例：{'ENTP','INFJ'}）
    if (f.mbtis != null && f.mbtis!.isNotEmpty) {
      final m = (p['mbti'] ?? '').toString().toUpperCase().trim();
      if (m.isEmpty) {
        // 未設定を含めないなら落とす
        if (f.includeNullMbti != true) return false;
      } else {
        final allow = f.mbtis!.map((e) => e.toUpperCase().trim()).toSet();
        if (!allow.contains(m)) return false;
      }
    }

    return true;
  }

  // --------- ヘルパー ---------
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// "175cm" や 175、"175" に対応して cm の整数へ
  int? _toHeightCm(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    final m = RegExp(r'(\d{2,3})').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Widget _refineNavIcon(userId) {
    final enabled = _canRefine; // ← refine_unlocked を見たゲッター
    final color   = enabled ? Colors.white : Colors.white38;

    return GestureDetector(
      onTap: () {
        if (!enabled) {
          goPaywall(context, userId: userId);
          return;
        }
        _openSearchFilters(); // 既存の遷移
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.tune_rounded, color: color),
          if (!enabled)
            Positioned(
              right: -6, top: -6,
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.white70, size: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopNavigationBar(
    BuildContext context,
    String userId,
    bool matchMultiple,
    void Function(bool) onToggleMatch,
    String? gender
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // ── Pマーク（ポイント） ──
          _SpotlightTargetCapture(
            registry: _spotlight,
            target: _TutorialTarget.pointsBadge,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PointExchangeScreen(userId: userId),
                  ),
                );
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey.shade800,
                    width: 4,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_parking,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ),

          // ── エリア選択 ──
          _SpotlightTargetCapture(
            registry: _spotlight,
            target: _TutorialTarget.areaSelect,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AreaSelectionScreen(userId: userId)),
                );
              },
              child: const Icon(Icons.place, color: Colors.white),
            ),
          ),

          // ── みんなで ──
          _SpotlightTargetCapture(
            registry: _spotlight,
            target: _TutorialTarget.groupMatch,
            child: GestureDetector(
              onTap: () => onToggleMatch(true),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group, color: Colors.white),
                  if (matchMultiple)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      height: 2,
                      width: 20,
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          ),

          // ── ひとりで ──
          _SpotlightTargetCapture(
            registry: _spotlight,
            target: _TutorialTarget.soloMatch,
            child: GestureDetector(
              onTap: () => onToggleMatch(false),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white),
                  if (!matchMultiple)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      height: 2,
                      width: 20,
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          ),

          // ── 絞り込み ──（ハイライト対象外）
          _refineNavIcon(userId),
        ],
      ),
    );
  }

  void _updateMatchMultiple(String userId, bool value) async {
    final url = Uri.parse('https://settee.jp/user-profile/$userId/update-match-multiple/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'match_multiple': value}),
    );

    if (response.statusCode == 200) {
      setState(() {
        isMatchMultiple = value;
        profiles.clear();
        currentPageIndex = 0;
      });
      await _fetchProfiles();
    } else {
      debugPrint("更新失敗: ${response.body}");
    }
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
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.home, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DiscoveryScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.search, color: Colors.black),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),  // 文字を少し上に配置
            child: Image.asset(
              'assets/logo_text.png',
              width: 70,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchedUsersScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.mail_outline, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.person_outline, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isLikeEffectActive => _activeLikeEffect != null;

  void _beginLikeEffect(LikeKind kind, {bool advanceAfter = true}) {
    _likeEffectTimer?.cancel();
    setState(() => _activeLikeEffect = kind); // ロックON

    _likeEffectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _activeLikeEffect = null); // ロックOFF
      if (advanceAfter) {
        _advanceIfPossible(); // 送信時は自動で次へ
      }
    });
  }

  // ── 前進の共通ヘルパ：ロック中・境界チェックを一か所で
  void _advanceIfPossible() {
    if (!mounted || _isLikeEffectActive) return;
    if (!_pageController.hasClients) return;

    final p = _pageController.page;
    if (p != null && p.round() < profiles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // 0=通常, 1=スーパー, 2=ごちそう, 3=メッセージ → LikeKind
  LikeKind? _kindFromType(int t) {
    switch (t) {
      case 1: return LikeKind.superLike;
      case 2: return LikeKind.treatLike;
      case 3: return LikeKind.messageLike;
    }
    return null;
  }

  @override
  void dispose() {
    _likeEffectTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── Likeボタン（有効/無効対応・ロック表示）
  Widget _iconLikeButton(
    IconData icon,
    int type,
    String receiverId, {
    double size = 50,
    required bool enabled,
    String? disabledReason,
    VoidCallback? onUsed,
  }) {
    final borderColor = enabled ? Colors.white : Colors.white24;
    final baseIconColor = enabled ? Colors.white : Colors.white38;

    bool isPressed = false; // builderの外で保持

    return StatefulBuilder(
      builder: (context, setInnerState) {
        Future<void> _handleTap() async {
          if (!enabled) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PaywallScreen(userId: widget.currentUserId)),
            );
            return;
          }

          // 通常Like：即次へ（押下中だけ赤）
          if (type == 0) {
            setInnerState(() => isPressed = true);
            await _sendLike(receiverId, type);

            // 相互Like成立ならマッチ画面を表示
            await _checkAndShowMatch(receiverId);

            // 次へ（※マッチ画面はフルスクリーンなので、出ていても裏で進むだけ）
            if (_pageController.page != null && _pageController.page!.round() < profiles.length - 1) {
              _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
            }

            setInnerState(() => isPressed = false);
            await _fetchEntitlements(widget.currentUserId);
            onUsed?.call();
            return;
          }

          // メッセージLike：入力必須
          if (type == 3) {
            final message = await _openMessageLikeSheet();
            if (message == null) return;

            setInnerState(() => isPressed = true);
            await _sendLike(receiverId, type, message: message);

            // 相互Like成立ならマッチ画面を表示
            await _checkAndShowMatch(receiverId);

            await Future.delayed(const Duration(milliseconds: 120));
            if (mounted) setInnerState(() => isPressed = false);

            _beginLikeEffect(LikeKind.messageLike);

            await _fetchEntitlements(widget.currentUserId);
            onUsed?.call();
            return;
          }


          // Super / Treat：演出→自動で次へ
          final kind = _kindFromType(type);

          // 演出開始よりも“先に”送って判定
          setInnerState(() => isPressed = true);
          await _sendLike(receiverId, type);

          // 相互Like成立ならマッチ画面を表示
          await _checkAndShowMatch(receiverId);

          if (kind != null) _beginLikeEffect(kind);

          await Future.delayed(const Duration(milliseconds: 120));
          if (mounted) setInnerState(() => isPressed = false);

          await _fetchEntitlements(widget.currentUserId);
          onUsed?.call();
        }

        final bool showRedBg = (type == 0 && isPressed);

        return GestureDetector(
          onTap: _handleTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (enabled)
                AnimatedOpacity(
                  opacity: isPressed ? 0.6 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedScale(
                    scale: isPressed ? 2.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      width: size, height: size,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: showRedBg ? const Color(0xFFFF3B30) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: showRedBg ? Colors.white : baseIconColor,
                    size: size * 0.5,
                  ),
                ),
              ),
              if (!enabled)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: size * 0.38, height: size * 0.38,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.white70, size: 16),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Likeボタン群（絶対配置）
  Widget _likeButtons(String userId) {
    return Stack(
      children: [
        // Super Like
        Positioned(
          bottom: 195,
          right: 75,
          child: _iconLikeButton(
            Icons.auto_awesome, 1, userId,
            enabled: _canSuperLike,
            disabledReason: 'スーパーライクの残数がありません。',
          ),
        ),

        // Message Like
        Positioned(
          bottom: 150,
          right: 95,
          child: _iconLikeButton(
            Icons.message, 3, userId,
            enabled: _canMessageLike,
            disabledReason: 'メッセージライクの残数がありません。',
          ),
        ),

        // Treat Like（残数ベース）
        Positioned(
          bottom: 107,
          right: 70,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _iconLikeButton(
                Icons.fastfood, 2, userId,
                enabled: _canTreatLike,
                disabledReason: 'ごちそうライクの残数がありません。',
              ),
              Positioned(
                right: -36, bottom: -5,
                child: Opacity(
                  opacity: _canTreatLike ? 1.0 : 0.4,
                  child: SizedBox(
                    width: 50, height: 30,
                    child: CustomPaint(
                      painter: MaskedBadgePainter(
                        overlapCenter: const Offset(-10, 0),
                        overlapRadius: 23,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        alignment: Alignment.center,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            children: [
                              TextSpan(text: 'マッチ率\n', style: TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.bold)),
                              TextSpan(text: '×1.5',    style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Normal Like
        Positioned(
          bottom: 140,
          right: 20,
          child: _iconLikeButton(Icons.thumb_up, 0, userId, size: 75, enabled: true),
        ),
      ],
    );
  }

  void _showMessageLikeOverlay(String text) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _MessageLikeOverlayCard(
        text: text,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // 現在表示中ユーザIDに対して、有料Likeの演出を出す
  void _checkIncomingPaidLikeFor(String viewedUserId) {
    if (_isLikeEffectActive) return;                // 送信側演出中は重ねない

    final ev = _receivedLikes[viewedUserId];
    if (ev == null) return;
    if (ev.type == 0) return; // 通常Likeは対象外

    // 既存のマッピング関数を再利用（0=通常,1=スーパー,2=ごちそう,3=メッセージ）
    final kind = _kindFromType(ev.type);
    if (kind == LikeKind.messageLike) {
      final text = (ev.message ?? '').trim();
      if (text.isNotEmpty) {
        _showMessageLikeOverlay(text);              // ★ 中央に本文
      } else {
        // 本文が無ければ共通演出だけでも
        _beginLikeEffect(kind!, advanceAfter: false);
      }
    } else if (kind != null) {
      _beginLikeEffect(kind, advanceAfter: false);  // ★ 自動前進はしない
    }
  }


  // 今日(JST)〜7日後(JST)に入る日付だけを抽出し、["月曜","火曜",...] を返す
  List<String> weekdaysFromIsoWithin7Days(List<String> isoDates) {
    // JSTの「今日」0:00
    final nowJst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final start = DateTime(nowJst.year, nowJst.month, nowJst.day);
    final end   = start.add(const Duration(days: 7)); // 両端含む

    // ユニークな曜日番号(1=Mon..7=Sun)を集める
    final seen = <int>{};

    for (final s in isoDates) {
      if (s.length < 10) continue;
      final y = int.tryParse(s.substring(0, 4));
      final m = int.tryParse(s.substring(5, 7));
      final d = int.tryParse(s.substring(8, 10));
      if (y == null || m == null || d == null) continue;

      // 日付のみ想定なのでUTCで生成（時差の影響を避ける）
      final dt = DateTime.utc(y, m, d);
      if (!dt.isBefore(start) && !dt.isAfter(end)) {
        seen.add(dt.weekday);
      }
    }

    const w = ['月','火','水','木','金','土','日'];
    final out = <String>[];
    for (var i = 1; i <= 7; i++) {
      if (seen.contains(i)) out.add('${w[i - 1]}曜');
    }
    return out;
  }

  String _val(Map<String, dynamic> p, String key) {
    final v = p[key];
    if (v == null) return '未設定';
    if (v is String && v.trim().isEmpty) return '未設定';
    return v.toString();
  }

  // === タグ（灰）: アイコン背景なし・const最適化 ===
  Widget _grayTag(String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF424242), // = Colors.grey[800]
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 2),
          ],
          // Row内で横幅に合わせて省略
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === タグ（灰・縦書き）: split()を廃止して単一Textへ ===
  // 例: "月曜" → "月\n曜" / "未" はそのまま
  Widget _grayTagVertical(String label, {IconData? icon}) {
    final String vertical =
        (label.length >= 2) ? '${label[0]}\n${label.substring(1)}' : label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF424242),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(height: 4),
          ],
          // 単一Textで2行表示（生成コスト・レイアウトとも軽い）
          Text(
            vertical,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10, height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // === タグ（白・固定幅）: const最適化 & 無駄な再レイアウト回避 ===
  Widget _whiteTag(String label, IconData icon, double width) {
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: Colors.black),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600, fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _widerItemWidth(BoxConstraints constraints,
      {required int columns, double spacing = 8.0, double wantFactor = 1.15, double minSpacing = 2.0}) {
    final baseWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
    double itemWidth = baseWidth * wantFactor;

    // 収まりチェック
    double total = itemWidth * columns + spacing * (columns - 1);
    if (total > constraints.maxWidth) {
      // spacing を詰めてリトライ
      spacing = minSpacing;
      final maxWidthPerItem = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      if (itemWidth > maxWidthPerItem) itemWidth = maxWidthPerItem;
    }
    return itemWidth;
  }

  // ── 左カラム：「基本情報」見出し＋2行3列グリッド
  Widget _leftBasicInfoBlock(Map<String, dynamic> profile) {
    final gender     = _val(profile, 'gender');
    final mbti       = _val(profile, 'mbti');
    final drinking   = _val(profile, 'drinking');
    final zodiac     = _val(profile, 'zodiac');
    final university = _val(profile, 'university');
    final smoking    = _val(profile, 'smoking');

    final rawItems = <Map<String, dynamic>>[
      {'label': gender,     'icon': Icons.wc},
      {'label': mbti,       'icon': Icons.psychology_alt},
      {'label': drinking,   'icon': Icons.local_bar},
      {'label': zodiac,     'icon': Icons.auto_awesome},
      {'label': university, 'icon': Icons.school},
      {'label': smoking,    'icon': Icons.smoking_rooms},
    ];

    // 「未設定」を除外
    final items = rawItems.where((e) {
      final label = (e['label'] as String?)?.trim() ?? '';
      return label.isNotEmpty && label != '未設定';
    }).toList();

    const reservedHeight = 110.0; // 見出し＋グリッドが収まる高さ

    // 全て未設定なら領域だけ確保（名前位置を固定）
    if (items.isEmpty) {
      return const SizedBox(height: reservedHeight);
    }

    // 3列固定。間隔を少し詰めて“広く見せる”
    const columns = 3;
    const crossSpacing = 6.0; // 横方向の間隔（広く見せたいなら 4.0 なども可）
    const mainSpacing  = 6.0; // 縦方向の間隔

    return SizedBox(
      height: reservedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 各セルの幅を算出し、その幅で白タグを描画
          final cellWidth = (constraints.maxWidth - crossSpacing * (columns - 1)) / columns;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '基本情報',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: crossSpacing,
                    mainAxisSpacing: mainSpacing,
                    // _whiteTag の高さ(32)＋若干のゆとりに合わせて比率調整
                    childAspectRatio: cellWidth / 24.0,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return _whiteTag(e['label'] as String, e['icon'] as IconData, cellWidth);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 2行1列の whiteTag（虫眼鏡アイコン）
  Widget _leftSeekingPreferenceBlock(Map<String, dynamic> profile) {
    final seeking    = _val(profile, 'seeking');
    final preference = _val(profile, 'preference');

    final labels = <String>[];
    if (seeking.trim().isNotEmpty && seeking != '未設定') {
      labels.add(seeking);
    }
    if (preference.trim().isNotEmpty && preference != '未設定') {
      labels.add(preference);
    }

    const reservedHeight = 110.0; // 名前位置を固定したい場合はこのまま
    if (labels.isEmpty) {
      return const SizedBox(height: reservedHeight);
    }

    // ▼ 調整ポイント：タグの「見た目の高さ」をここで決める（AspectRatio から算出される）
    const double tagVisualHeight = 24.0; // 22〜28 くらいで好みへ
    const double lineSpacing = 8.0;      // タグとタグの間隔

    return SizedBox(
      height: reservedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 1列の横幅（＝この幅に対して AspectRatio で高さが決まる）
          final double itemWidth = constraints.maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '求めているのは',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              for (int i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(height: lineSpacing),

                // 横幅固定 → AspectRatio で高さを統一
                SizedBox(
                  width: itemWidth,
                  child: AspectRatio(
                    // aspectRatio = width / height
                    aspectRatio: itemWidth / tagVisualHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _whiteTag(labels[i], Icons.search, itemWidth),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static const double _rightPanelReservedHeight = 80.0; // 右下パネルの固定高さ

  // 右端にエリア（最大4行1列）、左側に曜日（縦書きタグを“1行横並び”。全7日なら ALL を縦書き）
  // エリアが空でも曜日はパネルの縦中央に来る
  Widget _rightAreaAndDaysBlock(Map<String, dynamic> profile) {
    // --- エリア（最大4件、未設定や空は除外） ---
    final List<String> areas = ((profile['selected_area'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty && s != '未設定')
        .take(4)
        .toList();

    // --- 今日(JST)〜7日後(JST)に入る available_dates を曜日に変換 ---
    final List<String> isoDates = ((profile['available_dates'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    final nowJst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final start  = DateTime(nowJst.year, nowJst.month, nowJst.day);
    final end    = start.add(const Duration(days: 7));

    final seenWeekdays = <int>{};
    for (final s in isoDates) {
      if (s.length < 10) continue;
      final y = int.tryParse(s.substring(0, 4));
      final m = int.tryParse(s.substring(5, 7));
      final d = int.tryParse(s.substring(8, 10));
      if (y == null || m == null || d == null) continue;
      final dt = DateTime.utc(y, m, d);
      if (!dt.isBefore(start) && !dt.isAfter(end)) {
        seenWeekdays.add(dt.weekday); // 1..7
      }
    }

    const jp = ['月','火','水','木','金','土','日'];
    final bool isAllDays = seenWeekdays.length == 7;
    final List<String> dayLabels = isAllDays
        ? const []
        : [
            for (var i = 1; i <= 7; i++)
              if (seenWeekdays.contains(i)) '${jp[i - 1]}曜',
          ];

    return SizedBox(
      height: _rightPanelReservedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // ← ここをいじれば確実に見た目が変わります
          final double gapBetweenWeekdaysAndAreas = 2.0;   // 曜日⇔エリアの間
          final double weekdayChipGap = 2.0;                // 曜日タグ同士の間

          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左：曜日（縦中央・1行横並び・横スクロール）
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isAllDays)
                      _grayTag('ALL', icon: Icons.access_time) // ← 横書き
                    else if (dayLabels.isEmpty)
                      _grayTag('空きなし', icon: Icons.access_time)
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < dayLabels.length; i++) ...[
                              if (i > 0) SizedBox(width: weekdayChipGap),
                              _grayTagVertical(dayLabels[i], icon: Icons.access_time), // ← 曜日は縦書きのまま
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // 右：エリア（右端に縦1列、縦中央）
              if (areas.isNotEmpty)
                Padding(
                  // ★ ここが「曜日⇔エリア」のスペース。数値を変えれば確実に変わります
                  padding: EdgeInsets.only(left: gapBetweenWeekdaysAndAreas),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < areas.length; i++) ...[
                        if (i > 0) const SizedBox(height: 2),
                        _grayTag(areas[i], icon: Icons.place),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _blockUser(String blockerId, String blockedId) async {
    final uri = Uri.parse('https://settee.jp/block/');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'blocker': blockerId, 'blocked': blockedId}),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body);
      return body['error']?.toString() ?? 'ブロックに失敗しました (${res.statusCode})';
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<String?> _reportUser({
    required String targetId,
    String? reason, // 任意
  }) async {
    final uri = Uri.parse('https://settee.jp/report/');
    try {
      final payload = <String, dynamic>{
        'target': targetId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      };

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) return null; // OK
      // サーバ側のエラーメッセージを拾う
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        return body['detail']?.toString() ??
            body['error']?.toString() ??
            '通報に失敗しました (${res.statusCode})';
      } catch (_) {
        return '通報に失敗しました (${res.statusCode})';
      }
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  void _showUserActions(BuildContext context, Map user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: const Text('ブロック', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx); // 一旦閉じる
                  final ok = await _confirmBlock(context, user['nickname']);
                  if (ok != true) return;

                  final err = await _blockUser(widget.currentUserId, user['user_id']);
                  if (err == null) {
                    // 自分→相手の Like はサーバ側で即削除済み。UI からも除去
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ブロックしました')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orangeAccent),
                title: const Text('通報する', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirmReport(context, user['nickname']);
                  if (ok != true) return;

                  final err = await _reportUser(targetId: user['user_id']);
                  if (err == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('通報しました')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmBlock(BuildContext context, String nickname) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'block',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return Opacity(
          opacity: curved.value,
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block, color: Colors.redAccent, size: 36),
                      const SizedBox(height: 12),
                      Text('ブロックしますか？', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        '$nickname さんをブロックします。あなたからのLikeは削除され、相手とのやり取りは制限されます。',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2D55)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('ブロックする', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmReport(BuildContext context, String nickname) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'report',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return Opacity(
          opacity: curved.value,
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag_outlined, color: Color.fromARGB(255, 153, 87, 0), size: 36),
                      const SizedBox(height: 12),
                      Text('通報しますか？', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        '$nickname さんを運営に通報します。',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 153, 87, 0)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('通報する', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showEmptyState
            ? _buildEmptyState()
            : NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  if (_isLikeEffectActive) return true;

                  if (notification.dragDetails != null &&
                      notification.metrics.axis == Axis.vertical &&
                      notification.scrollDelta! < 0 &&
                      _pageController.page != null &&
                      _pageController.page!.round() > 0) {
                    _pageController.jumpToPage(_pageController.page!.round());
                    return true;
                  }
                  return false;
                },
                child: Stack(
                  children: [
                    IgnorePointer(
                      ignoring: _isLikeEffectActive,
                      child: PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        physics: _isLikeEffectActive
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        itemCount: profiles.length,
                        onPageChanged: (index) {
                          if (_isLikeEffectActive) return; // 演出中の副作用停止
                          setState(() => currentPageIndex = index);

                          final viewedUserId = profiles[index]['user_id'];
                          _checkIncomingPaidLikeFor(viewedUserId);
                        },
                        itemBuilder: (context, index) {
                          final profile = profiles[index];
                          // 0=1枚目, 1=2枚目, 2+=3枚目以降
                          final imgIdx = imageIndexes[profile['user_id']] ?? 0;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onDoubleTap: () {
                                  if (_isLikeEffectActive) return;
                                  _sendLike(profile['user_id'], 0);
                                  if (_pageController.page != null &&
                                      _pageController.page!.round() < profiles.length - 1) {
                                    _pageController.nextPage(
                                      duration: const Duration(milliseconds: 500),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                },
                                child: _buildProfileImage(profile['user_id']),
                              ),

                              SafeArea(
                                child: Column(
                                  children: [
                                    _buildTopNavigationBar(
                                      context,
                                      widget.currentUserId,
                                      isMatchMultiple ?? true,
                                      (bool newValue) => _updateMatchMultiple(widget.currentUserId, newValue),
                                      profile['gender'],
                                    ),

                                    // カレンダー
                                    _buildCalendar(),

                                    // ★ カレンダー直下のバナー（GlobalKey不要）
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 250),
                                      switchInCurve: Curves.easeOut,
                                      switchOutCurve: Curves.easeIn,
                                      child: (_activeLikeEffect == null)
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                              child: _LikeFlowBanner(
                                                // ★ 3秒で中央→右へ流れる
                                                duration: const Duration(milliseconds: 3000),
                                                child: _BannerImage(
                                                  assetPath: kLikeBannerAsset[_activeLikeEffect]!,
                                                ),
                                              ),
                                            ),
                                    ),


                                    const Spacer(),
                                  ],
                                ),
                              ),

                              if (_activeLikeEffect != null)
                                _BottomTintPanel(
                                  color: kLikeTintColor[_activeLikeEffect]!,
                                  height: 200, // 好みで 160〜240 など
                                ),


                              _likeButtons(profile['user_id']),

                              // 戻るボタン（Settee Vip 有効時のみ有効）
                              Positioned(
                                bottom: 180,
                                left: 30,
                                child: GestureDetector(
                                  onTap: () {
                                    if (!_backtrackEnabled) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PaywallScreen(userId: widget.currentUserId),
                                        ),
                                      );
                                      return;
                                    }
                                    if (_pageController.page != null &&
                                        _pageController.page!.round() > 0) {
                                      _pageController.previousPage(
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Opacity(
                                        opacity: _backtrackEnabled ? 1.0 : 0.6,
                                        child: Container(
                                          width: 35,
                                          height: 35,
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _backtrackEnabled ? Colors.white : Colors.white24,
                                              width: 3,
                                            ),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.keyboard_arrow_up_outlined,
                                              color: _backtrackEnabled ? Colors.white : Colors.white38,
                                              size: 30,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!_backtrackEnabled)
                                        Positioned(
                                          right: -6,
                                          top: -6,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.65),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white24),
                                            ),
                                            child: const Icon(Icons.lock_rounded, color: Colors.white70, size: 10),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // ★ 65%（白） : 35%（灰）で横幅を割り当てる共通オーバーレイ
                              Positioned(
                                bottom: 15,
                                left: 5,
                                right: 5,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final totalW  = constraints.maxWidth;
                                    final leftW   = totalW * 0.65; // 白タグ領域
                                    final rightW  = totalW * 0.33; // 灰タグ領域

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.end, // 右側パネルの高さに合わせて下揃え
                                      children: [
                                        // 左：白タグ領域（名前＋基本情報/求めているのは）
                                        SizedBox(
                                          width: leftW,
                                          child: (imgIdx <= 1)
                                              ? Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '${profile['nickname']}  ${profile['age']}',
                                                            style: GoogleFonts.notoSansJp(
                                                              textStyle: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 25,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        _UserActionsMenuButton(
                                                          onTap: () {
                                                            // 既存のボトムシートをそのまま呼ぶ
                                                            _showUserActions(context, {
                                                              'user_id': profile['user_id'],
                                                              'nickname': profile['nickname'],
                                                            });
                                                          },
                                                        ),
                                                      ],
                                                    ),

                                                    const SizedBox(height: 6),

                                                    // 1枚目＝基本情報、2枚目＝求めているのは（いずれも未設定は非表示＋高さ予約済）
                                                    if (imgIdx == 0)
                                                      _leftBasicInfoBlock(profile)
                                                    else
                                                      _leftSeekingPreferenceBlock(profile),
                                                  ],
                                                )
                                              : const SizedBox.shrink(), // 3枚目以降は非表示（横幅は確保したままでもOKにしたい場合はここで高さ確保用のBoxに変更可）
                                        ),
                                        SizedBox(width: totalW * 0.02),
                                        // 右：灰タグ領域（エリア＋曜日）
                                        SizedBox(
                                          width: rightW,
                                          child: Align(
                                            alignment: Alignment.bottomRight,
                                            child: _rightAreaAndDaysBlock(profile), // ← 既存の右パネル（高さは内部の _rightPanelReservedHeight に準拠）
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // 左端の進捗バー
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 10,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildVerticalProgressBar(
                            currentPageIndex, profiles.length),
                      ),
                    ),
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.currentUserId),
    );
  }

  /// 進捗バーウィジェット
  Widget _buildVerticalProgressBar(int currentIndex, int totalCount) {
    int topDots = 0;
    int bottomDots = 0;

    if (currentIndex == 0) {
      topDots = 0;
      bottomDots = 5;
    } else if (currentIndex == 1) {
      topDots = 1;
      bottomDots = 4;
    } else if (currentIndex == 2) {
      topDots = 2;
      bottomDots = 3;
    } else if (currentIndex >= 3 && currentIndex < totalCount - 2) {
      topDots = 3;
      bottomDots = 2;
    } else if (currentIndex == totalCount - 2) {
      topDots = 4;
      bottomDots = 1;
    } else if (currentIndex == totalCount - 1) {
      topDots = 5;
      bottomDots = 0;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey(currentIndex),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(topDots, (_) => _buildWhiteDot()),
          _buildGrayBar(),
          ...List.generate(bottomDots, (_) => _buildWhiteDot()),
        ],
      ),
    );
  }

  Widget _buildWhiteDot() {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildGrayBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      width: 8,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
    );
  }

  List<Color> _generateGradientFromColor(Color baseColor) {
    // 明るさを調整してグラデーションを作成
    final hsl = HSLColor.fromColor(baseColor);
    final lighter = hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    final darker = hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();

    return [lighter, darker];
  }

  Widget _likeButton(
    String label,
    int type,
    String receiverId,
    Color color, {
    double size = 60,
  }) {
    final bool isNormalLike = (type == 0);

    return GestureDetector(
      onTap: () => _sendLike(receiverId, type),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isNormalLike
                ? [Color.fromARGB(255, 0, 255, 238), Color.fromARGB(255, 0, 13, 255)]
                : _generateGradientFromColor(color),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label.replaceAll(" ", "\n"),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isNormalLike ? Colors.white : Colors.black,
            fontSize: isNormalLike ? (size / 4) * 1.5 : (size / 5.5),
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

// 中央→右へ“流れる”演出用バナー
class _LikeFlowBanner extends StatefulWidget {
  const _LikeFlowBanner({
    Key? key,
    required this.duration,
    required this.child,
  }) : super(key: key);

  final Duration duration;
  final Widget child;

  @override
  State<_LikeFlowBanner> createState() => _LikeFlowBannerState();
}

class _LikeFlowBannerState extends State<_LikeFlowBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Alignment> _align;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);

    // 中央 → 右端の少し外（1.2）まで流す
    _align = AlignmentTween(
      begin: Alignment.center,
      end: const Alignment(1.2, 0.0),
    ).animate(curve);

    // 後半で薄く消える
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.65, 1.0)),
    );

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 横幅は必ずフルに確保（高さは子に合わせる）
    return Row(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              return Align(
                alignment: _align.value,
                child: Opacity(
                  opacity: _fade.value,
                  child: widget.child,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MaskedBadgePainter extends CustomPainter {
  final Offset overlapCenter;
  final double overlapRadius;

  MaskedBadgePainter({required this.overlapCenter, required this.overlapRadius});

  @override
  void paint(Canvas canvas, Size size) {
    // 新しいレイヤーに描画（これが重要）
    final Paint layerPaint = Paint();
    canvas.saveLayer(Offset.zero & size, layerPaint);

    // Step 1: バッジ背景描画（白）
    final badgePaint = Paint()..color = Colors.white;
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(4),
    );
    canvas.drawRRect(badgeRRect, badgePaint);

    // Step 2: くり抜き（透明化）
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear;
    canvas.drawCircle(overlapCenter, overlapRadius, clearPaint);

    // レイヤーの描画を反映
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

enum BubbleArrowDirection { up, down, left, right }

class _TutorialPageData {
  final String title;
  final String message;
  final BubbleArrowDirection arrow;
  final Alignment bubbleAlignment;
  final EdgeInsets edgePadding;
  final double arrowOffset;
  final double arrowInset;
  final String? imageAsset;
  final double? imgHeightFracInBubble;
  final double? imgWidthFactor;

  _TutorialPageData({
    required this.title,
    required this.message,
    required this.arrow,
    required this.bubbleAlignment,
    required this.edgePadding,
    this.arrowOffset = 0.5,
    this.arrowInset = double.nan,
    this.imageAsset,
    this.imgHeightFracInBubble,
    this.imgWidthFactor,
  });
}

class _Dots extends StatelessWidget {
  final int current, length;

  // サイズは好みで調整できます（アクティブと非アクティブで少し差をつける例）
  final double activeSize;
  final double inactiveSize;

  const _Dots({
    required this.current,
    required this.length,
    this.activeSize = 12.0,
    this.inactiveSize = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final bool active = i == current;
        final double size = active ? activeSize : inactiveSize;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: size,                  // ← 正円にするため width = height
          height: size,                 // ← 正円にするため width = height
          decoration: const BoxDecoration(
            shape: BoxShape.circle,     // ← 正円
            // 色は固定：アクティブ=黒 / 非アクティブ=白
          ),
          // 色はdecorationではなく Container の color にすると const を崩さないため外側に:
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.black : Colors.white,
          ),
        );
      }),
    );
  }
}

/// 角丸＋影＋三角。矢印位置を可変にできます。
class _SpeechBubble extends StatelessWidget {
  final Widget child;
  final BubbleArrowDirection direction;
  final double arrowOffset;     // 上/下：0.0(左)〜1.0(右)
  final double arrowInset;      // 左/右：上からのpx
  final double maxHeightFraction; // 画面高に対する最大高さ割合

  const _SpeechBubble({
    required this.child,
    this.direction = BubbleArrowDirection.up,
    this.arrowOffset = 0.5,
    this.arrowInset = double.nan,
    this.maxHeightFraction = 0.60,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screenH = MediaQuery.of(context).size.height;
      final maxBubbleH = screenH * maxHeightFraction;

      final w = math.min(constraints.maxWidth, 520.0);
      const arrowW = 24.0;
      const arrowH = 14.0;

      final borderRadius = BorderRadius.circular(22);
      final bubble = Container(
        width: w, // ← ここはそのまま（バブルの実幅を固定）
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
          boxShadow: const [
            BoxShadow(blurRadius: 28, spreadRadius: 2, offset: Offset(0, 10), color: Color(0x33000000)),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(                    // ★ ここを ConstrainedBox → SizedBox
            height: maxBubbleH,              // ★ 子に“ぴったり”の高さを渡す
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
              child: child,
            ),
          ),
        ),
      );
      final double? posTop =
          direction == BubbleArrowDirection.up ? -arrowH : null;
      final double? posBottom =
          direction == BubbleArrowDirection.down ? -arrowH : null;
      final double? posLeft = (direction == BubbleArrowDirection.left)
          ? -arrowH
          : (direction == BubbleArrowDirection.up ||
                  direction == BubbleArrowDirection.down)
              ? (w - arrowW) * arrowOffset.clamp(0.0, 1.0)
              : null;
      final double? posRight =
          direction == BubbleArrowDirection.right ? -arrowH : null;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            top: posTop,
            bottom: posBottom,
            left: posLeft,
            right: posRight,
            child: (direction == BubbleArrowDirection.left ||
                    direction == BubbleArrowDirection.right)
                ? SizedBox(
                    width: w,
                    child: Align(
                      alignment: direction == BubbleArrowDirection.left
                          ? Alignment.topLeft
                          : Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: arrowInset.isNaN ? 0 : arrowInset,
                        ),
                        child: CustomPaint(
                          size: const Size(arrowH, arrowW),
                          painter: _SideTrianglePainter(
                            color: Colors.white,
                            right: direction == BubbleArrowDirection.right,
                          ),
                        ),
                      ),
                    ),
                  )
                : CustomPaint(
                    size: const Size(arrowW, arrowH),
                    painter: _TopBottomTrianglePainter(
                      color: Colors.white,
                      upside: direction == BubbleArrowDirection.up,
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

class _TopBottomTrianglePainter extends CustomPainter {
  final Color color;
  final bool upside; // true:上, false:下
  const _TopBottomTrianglePainter({required this.color, required this.upside});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path();
    if (upside) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path..close(), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SideTrianglePainter extends CustomPainter {
  final Color color;
  final bool right; // true:右向き、false:左向き
  const _SideTrianglePainter({required this.color, required this.right});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path();
    if (right) {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    }
    canvas.drawPath(path..close(), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 1) ハイライト対象の列挙
enum _TutorialTarget { soloMatch, groupMatch, areaSelect, pointsBadge, calendar }

class _GuidePage {
  final String title;
  final String message;
  final BubbleArrowDirection arrow;
  final Alignment bubbleAlignment;
  final EdgeInsets edgePadding;
  final double arrowOffset;
  final double arrowInset;
  final String? imageAsset;
  final double? imgHeightFracInBubble;
  final double? imgWidthFactor;

  // くり抜き用
  final _TutorialTarget highlightTarget;
  final EdgeInsets? highlightPadding;
  final bool? highlightAsCircle;

  const _GuidePage({
    required this.title,
    required this.message,
    required this.arrow,
    required this.bubbleAlignment,
    required this.edgePadding,
    this.arrowOffset = 0.5,
    this.arrowInset = double.nan,
    this.imageAsset,
    this.imgHeightFracInBubble,
    this.imgWidthFactor,
    required this.highlightTarget,
    this.highlightPadding,
    this.highlightAsCircle,
  });
}

// 3) レイアウト矩形を保管するレジストリ（GlobalKey不要）
class _SpotlightRegistry extends ChangeNotifier {
  final Map<_TutorialTarget, Rect> _rects = {};
  RenderBox? _coordSpace; // ← nullable に

  void setCoordinateSpace(RenderBox? box) {
    // 同じ参照なら何もしない
    if (identical(_coordSpace, box)) return;
    _coordSpace = box;
    notifyListeners(); // 基準変更を通知（再測定を促す）
  }

  RenderBox? get coordinateSpace => _coordSpace;

  void setRect(_TutorialTarget t, Rect r) {
    if (r.isEmpty) return;
    final old = _rects[t];
    if (old == null || _rectChanged(old, r)) {
      _rects[t] = r;
      notifyListeners();
    }
  }
  Rect? getRect(_TutorialTarget t) => _rects[t];

  bool _rectChanged(Rect a, Rect b) {
    const posTol = 0.5, sizeTol = 0.5;
    final dx = (a.left - b.left).abs() + (a.top - b.top).abs();
    final ds = (a.width - b.width).abs() + (a.height - b.height).abs();
    return dx > posTol || ds > sizeTol;
  }
}

// 4) 子ウィジェットのスクリーン座標Rectを取得してレジストリへ登録
class _SpotlightTargetCapture extends StatefulWidget {
  final Widget child;
  final _TutorialTarget target;
  final _SpotlightRegistry registry;

  const _SpotlightTargetCapture({
    required this.child,
    required this.target,
    required this.registry,
  });

  @override
  State<_SpotlightTargetCapture> createState() => _SpotlightTargetCaptureState();
}

class _SpotlightTargetCaptureState extends State<_SpotlightTargetCapture> {
  void _post() {
    if (!mounted) return;

    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached) return;

    final ancestor = widget.registry.coordinateSpace;

    // overlay がまだ準備できていない / 既に消えた → 次フレームで再試行
    if (ancestor == null || !ancestor.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _post();
      });
      return;
    }

    try {
      final offset = render.localToGlobal(Offset.zero, ancestor: ancestor);
      final size = render.size;
      final rect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      widget.registry.setRect(widget.target, rect);
    } on FlutterError {
      // まれに「別ツリー」例外が飛ぶ場合は、次フレームで座標空間の再登録→再測定
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _post();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _post(); });
  }

  @override
  void didUpdateWidget(covariant _SpotlightTargetCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _post(); });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((__) { if (mounted) _post(); });
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}

// 5) くり抜きオーバーレイ
class _SpotlightOverlay extends StatefulWidget {
  final _SpotlightRegistry registry;
  final _TutorialTarget target;
  final EdgeInsets padding;
  final bool asCircle;
  final double overlayOpacity;
  final Color dimColor;

  const _SpotlightOverlay({
    super.key,
    required this.registry,
    required this.target,
    this.padding = EdgeInsets.zero,
    this.asCircle = false,
    this.overlayOpacity = 0.6,
    this.dimColor = Colors.black,
  });

  @override
  State<_SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<_SpotlightOverlay> {
  void _registerCoordinateSpace() {
    if (!mounted) return;
    final rb = context.findRenderObject();
    if (rb is RenderBox && rb.attached) {
      widget.registry.setCoordinateSpace(rb);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerCoordinateSpace());
  }

  @override
  void didUpdateWidget(covariant _SpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerCoordinateSpace());
  }

  @override
  void dispose() {
    // 自分が消える＝座標空間も無効。クリアして計測側の ancestor 参照を断つ
    widget.registry.setCoordinateSpace(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.registry.getRect(widget.target);
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _SpotlightPainter(
          holeRect: rect == null ? Rect.zero : widget.padding.inflateRect(rect),
          asCircle: widget.asCircle,
          dimColor: widget.dimColor.withValues(alpha: widget.overlayOpacity),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect holeRect;
  final bool asCircle;
  final Color dimColor;

  _SpotlightPainter({
    required this.holeRect,
    required this.asCircle,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景を暗く塗る
    final overlayPaint = Paint()..color = dimColor;
    // レイヤーに描いてからBlendMode.clearで穴を開ける
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlayPaint);

    if (!holeRect.isEmpty) {
      final clearPaint = Paint()..blendMode = BlendMode.clear;
      if (asCircle) {
        final center = holeRect.center;
        final radius = (holeRect.size.longestSide) / 2;
        canvas.drawCircle(center, radius, clearPaint);
      } else {
        final rrect = RRect.fromRectAndRadius(holeRect, const Radius.circular(12));
        canvas.drawRRect(rrect, clearPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect ||
           oldDelegate.asCircle != asCircle ||
           oldDelegate.dimColor != dimColor;
  }
}

enum KycResult { cancelled, submitted }

class KycFlowScreen extends StatefulWidget {
  final String userId;
  const KycFlowScreen({super.key, required this.userId});
  @override
  State<KycFlowScreen> createState() => _KycFlowScreenState();
}

class _KycFlowScreenState extends State<KycFlowScreen> with WidgetsBindingObserver {
  // ===== 進行状態 =====
  int _step = 0; // 0:年齢確認, 1:書類選択, 2:権限説明/チェック, 3:表, 4:裏, 5:顔, 6:完了
  bool _ageVerified = false;
  String? _docType; // 'license' | 'passport' | 'mynumber_student' | 'insurance_student'

  // ===== 撮影データ =====
  XFile? _front, _back, _face;
  XFile? _front2, _back2; // ← 2種類目の書類（学生証）の表・裏

  bool _didPreflightCamera = false;
  bool _openingCamera = false;
  bool _didRetryCameraOnce = false;
  bool _uploading = false;
  double _uploadStepProgress = 0.0;

  bool get _isCombo => _docType == 'mynumber_student' || _docType == 'insurance_student';

  // 顔/完了のステップ番号（動的）
  int get _faceStep => _isCombo ? 7 : 5;
  int get _doneStep => _faceStep + 1;

  String get _primaryDocLabel {
    switch (_docType) {
      case 'mynumber_student': return 'マイナンバーカード';
      case 'insurance_student': return '健康保険証';
      case 'license': return '運転免許証';
      case 'passport': return 'パスポート';
      default: return '身分証';
    }
  }
  String get _secondaryDocLabel => '学生証';

  // ===== ライフサイクル監視（設定アプリからの復帰検知） =====
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final granted = await Permission.camera.isGranted;
      if (!mounted) return;
      if (granted && _step == 2) {
        setState(() => _step = 3); // 設定から戻ったら自動で撮影に進む
      }
    }
  }

  Future<void> _preflightCameraRequestStrong() async {
    if (_didPreflightCamera) return;
    _didPreflightCamera = true;

    var s = await Permission.camera.status;

    // 端末側でカメラ自体が禁止（スクリーンタイム/MDM）の場合は何をしてもトグルは出ません
    if (s.isRestricted) return;

    // まず普通に request（ここで許可されればベスト）
    if (s.isDenied || s.isLimited) {
      s = await Permission.camera.request();
      if (s.isGranted) return;
    }

    // まだ未許可（= NotDetermined/Denied 継続）の場合、UI を出さずに CameraController を初期化
    // iOS はここで “このアプリがカメラを使おうとした” が登録され、設定にトグルが出ます。
    try {
      final cams = await availableCameras();               // ここで権限確認が走る
      final desc = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        desc,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();                             // 実際のセッション開始（UI なし）
      await ctrl.dispose();
    } catch (e) {
      // 権限なしや初期化失敗でも OK。目的は“登録”なので握りつぶす。
      debugPrint('[preflight] initialize failed: $e');
    }
  }

  Future<XFile?> _openInlineCamera({required bool frontCamera}) async {
    if (_openingCamera) return null;
    _openingCamera = true;
    try {
      final ok = await _ensureCameraPermission();
      if (!ok) return null;

      // 端末のカメラ列挙
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _showAlert('カメラが見つかりません', 'この端末ではカメラが利用できません。');
        return null;
      }
      final desc = frontCamera
          ? (cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first))
          : (cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,  orElse: () => cams.first));

      // ★ controller は作らず、desc を渡して撮影ページに責務を集約
      final file = await Navigator.of(context).push<XFile>(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => _InlineCameraPage(description: desc),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          opaque: true,
        ),
      );
      return file;
    } on CameraException catch (e) {
      _showAlert('カメラ初期化エラー', e.description ?? e.code);
      return null;
    } finally {
      _openingCamera = false;
    }
  }

  Future<void> _uploadOne({
    required String userId,
    required int imageIndex, // 1=表, 2=裏, 3=顔
    required XFile xfile,
    String? bearerToken,     // 認証が必要なら使用
  }) async {
    // ← ここでハードコーディング
    final uri = Uri.parse('https://settee.jp/api/admin/upload_user_image/');

    final req = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..fields['image_index'] = imageIndex.toString();

    // 元ファイルをそのまま送る（フォーマット不問／拡張子もそのまま）
    final file = File(xfile.path);
    req.files.add(await http.MultipartFile.fromPath(
      'image',
      file.path,
      filename: file.path.split('/').last,
      // contentType は指定しない（JPEG固定をやめる）
      // contentType: MediaType('image', 'jpeg'),
    ));

    if (bearerToken != null) {
      req.headers['Authorization'] = 'Bearer $bearerToken';
    }

    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200) {
      throw Exception('アップロード失敗 (index=$imageIndex, status=${resp.statusCode}): $body');
    }
  }

  // ===== 権限確保：アプリ内導線（設定を開く→復帰で再チェック） =====
  Future<bool> _ensureCameraPermission() async {
    var s = await Permission.camera.status;

    // 1) すでに許可
    if (s.isGranted) return true;

    // 2) 端末レベルで禁止（スクリーンタイム/MDM）
    if (s.isRestricted) {
      await _showPermissionSheet(
        title: 'カメラが制限されています',
        message: 'スクリーンタイムや管理プロファイルでカメラが禁止されています。端末の設定で解除してください。',
        positiveText: 'OK',
        negativeText: '閉じる',
      );
      return false;
    }

    // 3) まだ未許可なら1度だけ request
    if (s.isDenied || s.isLimited) {
      s = await Permission.camera.request();
      if (s.isGranted) return true;
      // 注意: ここで permanentlyDenied に遷移してしまう端末がある
    }

    // 4) permission_handler は拒否判定だが、実アクセスは通るケースへのフォールバック
    //    （iOSで稀に発生。実際に初期化できればOK扱いにする）
    final okByInit = await _canInitializeCameraSilently();
    if (okByInit) {
      return true;
    }

    // 5) それでもダメな場合のみ設定誘導（ここで初めて出す）
    final open = await _showPermissionSheet(
      title: 'カメラの許可が必要です',
      message: '本人確認の撮影にカメラを使用します。「設定」からカメラを許可してください。',
      positiveText: '設定を開く',
      negativeText: 'キャンセル',
    );
    if (open == true) await openAppSettings();
    return false;
  }

  /// 実際に UI なしでカメラを初期化してみて、成功したら「使える」とみなすワークアラウンド
  Future<bool> _canInitializeCameraSilently() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return false;
      final desc = cams.first;
      final ctrl = CameraController(
        desc,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      await ctrl.dispose();
      return true;
    } on CameraException catch (e) {
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool?> _showPermissionSheet({
    required String title,
    required String message,
    String positiveText = 'OK',
    String negativeText = 'キャンセル',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
            ),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(negativeText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1FD27C), foregroundColor: Colors.white),
                    child: Text(positiveText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ===== 送信（APIに接続してください） =====
  Future<void> _submitAll() async {
    // 必須チェックをパターンごとに
    if (_isCombo) {
      if (_front == null || _back == null || _front2 == null || _back2 == null || _face == null) {
        _showAlert('未撮影の項目があります', '主書類（表・裏）と学生証（表・裏）、顔の5枚を撮影してください。');
        return;
      }
    } else {
      if (_front == null || _back == null || _face == null) {
        _showAlert('未撮影の項目があります', '表・裏・顔の3枚を撮影してください。');
        return;
      }
    }

    setState(() { _uploading = true; _uploadStepProgress = 0.0; });

    final userId = widget.userId;
    final token = null;
    final total = _isCombo ? 5 : 3;
    int done = 0;

    try {
      // 1) 表
      await _uploadOne(userId: userId, imageIndex: 1, xfile: _front!, bearerToken: token);
      if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);

      // 2) 裏
      await _uploadOne(userId: userId, imageIndex: 2, xfile: _back!, bearerToken: token);
      if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);

      if (_isCombo) {
        // 3) 学生証 表
        await _uploadOne(userId: userId, imageIndex: 3, xfile: _front2!, bearerToken: token);
        if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);
        // 4) 学生証 裏
        await _uploadOne(userId: userId, imageIndex: 4, xfile: _back2!, bearerToken: token);
        if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);
        // 5) 顔
        await _uploadOne(userId: userId, imageIndex: 5, xfile: _face!, bearerToken: token);
        if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);
      } else {
        // 3) 顔（単体パターン）
        await _uploadOne(userId: userId, imageIndex: 3, xfile: _face!, bearerToken: token);
        if (!mounted) return; setState(() => _uploadStepProgress = (++done) / total);
      }

      // 成功で完了画面へ
      if (!mounted) return;
      setState(() => _step = _doneStep);
    } catch (e) {
      if (!mounted) return;
      _showAlert('アップロードに失敗しました', '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ===== ナビゲーション簡易ヘルパー =====
  void _goNext() => setState(() => _step++);
  void _goPrev() {
      final next = _step - 1;
      setState(() => _step = _ageVerified ? next.clamp(1, 6) : next.clamp(0, 6));
  }

  // ===== 画面描画 =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: switch (_step) {
            0 => _AgeGate(onNext: () {
                setState(() {
                  _ageVerified = true;
                  _step = 1;  
                });
            }),
            1 => _DocSelect(
              onSelect: (t) => setState(() { _docType = t; _step = 2; }),
              onBack: _goPrev,
            ),
            2 => _CameraPermissionInfo(
              onNext: () async { await _preflightCameraRequestStrong(); if (!mounted) return; setState(() => _step = 3); },
              onBack: _goPrev,
            ),
            // 3: 主書類 表
            3 => _CaptureStep(
              title: '写真の確認\n${_primaryDocLabel}の“表面”を\n撮影してください',
              previewFile: _front,
              onBack: _goPrev,
              onRetake: () async { final f = await _openInlineCamera(frontCamera: false); if (!mounted) return; setState(() => _front = f); },
              onPrimary: () async {
                if (_front == null) {
                  final f = await _openInlineCamera(frontCamera: false);
                  if (!mounted) return; setState(() => _front = f);
                } else {
                  _goNext();
                }
              },
              primaryText: _front == null ? '撮影する' : '提出する',
            ),
            // 4: 主書類 裏
            4 => _CaptureStep(
              title: '写真の確認\n${_primaryDocLabel}の“裏面”を\n撮影してください',
              previewFile: _back,
              onBack: _goPrev,
              onRetake: () async { final f = await _openInlineCamera(frontCamera: false); if (!mounted) return; setState(() => _back = f); },
              onPrimary: () async {
                if (_back == null) {
                  final f = await _openInlineCamera(frontCamera: false);
                  if (!mounted) return; setState(() => _back = f);
                } else {
                  _goNext();
                }
              },
              primaryText: _back == null ? '撮影する' : '提出する',
            ),
            // 5: コンボなら 学生証 表 / 単体なら 顔
            5 => _isCombo
              ? _CaptureStep(
                  title: '写真の確認\n${_secondaryDocLabel}の“表面”を\n撮影してください',
                  previewFile: _front2,
                  onBack: _goPrev,
                  onRetake: () async { final f = await _openInlineCamera(frontCamera: false); if (!mounted) return; setState(() => _front2 = f); },
                  onPrimary: () async {
                    if (_front2 == null) {
                      final f = await _openInlineCamera(frontCamera: false);
                      if (!mounted) return; setState(() => _front2 = f);
                    } else { _goNext(); }
                  },
                  primaryText: _front2 == null ? '撮影する' : '提出する',
                )
              : _CaptureStep(
                  title: '顔認証の確認',
                  subtitle: 'マスク等を外し、逆光を避けて撮影してください。\n撮影データは本人確認のみに使用されます。',
                  previewFile: _face,
                  isFace: true,
                  onBack: _goPrev,
                  onRetake: () async { final f = await _openInlineCamera(frontCamera: true); if (!mounted) return; setState(() => _face = f); },
                  onPrimary: () async {
                    if (_face == null) {
                      final f = await _openInlineCamera(frontCamera: true);
                      if (!mounted) return; setState(() => _face = f);
                    } else { await _submitAll(); }
                  },
                  primaryText: _face == null ? '撮影する' : '提出する',
                ),
            // 6: コンボなら 学生証 裏 / 単体なら 完了
            6 => _isCombo
              ? _CaptureStep(
                  title: '写真の確認\n${_secondaryDocLabel}の“裏面”を\n撮影してください',
                  previewFile: _back2,
                  onBack: _goPrev,
                  onRetake: () async { final f = await _openInlineCamera(frontCamera: false); if (!mounted) return; setState(() => _back2 = f); },
                  onPrimary: () async {
                    if (_back2 == null) {
                      final f = await _openInlineCamera(frontCamera: false);
                      if (!mounted) return; setState(() => _back2 = f);
                    } else { _goNext(); }
                  },
                  primaryText: _back2 == null ? '撮影する' : '提出する',
                )
              : _SubmitDone(onClose: () {
                  Navigator.of(context, rootNavigator: true).pop(KycResult.submitted);
                }),
            // 7: コンボの 顔
            7 => _CaptureStep(
                  title: '顔認証の確認',
                  subtitle: 'マスク等を外し、逆光を避けて撮影してください。\n撮影データは本人確認のみに使用されます。',
                  previewFile: _face,
                  isFace: true,
                  onBack: _goPrev,
                  onRetake: () async { final f = await _openInlineCamera(frontCamera: true); if (!mounted) return; setState(() => _face = f); },
                  onPrimary: () async {
                    if (_face == null) {
                      final f = await _openInlineCamera(frontCamera: true);
                      if (!mounted) return; setState(() => _face = f);
                    } else { await _submitAll(); }
                  },
                  primaryText: _face == null ? '撮影する' : '提出する',
                ),
            // 8: コンボの 完了
            8 => _SubmitDone(onClose: () {
                  Navigator.of(context, rootNavigator: true).pop(KycResult.submitted);
                }),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
  
  void _showAlert(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

// ====== 以下は見た目部品 ======
class _AgeGate extends StatelessWidget {
  final VoidCallback onNext;
  const _AgeGate({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(24),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.verified_user, size: 56, color: Color(0xFF16C784)),
            const SizedBox(height: 12),
            const Text('年齢確認が必要です', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 6),
            const Text('規約に基づき、年齢確認を実施しています', textAlign: TextAlign.center, style: TextStyle(color: Colors.black)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FD27C), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: onNext,
                child: const Text('年齢確認をする', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DocSelect extends StatelessWidget {
  final void Function(String) onSelect;
  final VoidCallback onBack;
  const _DocSelect({required this.onSelect, required this.onBack});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, String key) => OutlinedButton(
      onPressed: () => onSelect(key),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFF16C784), width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        foregroundColor: const Color(0xFF16C784),
        minimumSize: const Size(double.infinity, 52),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('本人確認書類を\n選択してください',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('次のいずれかで提出してください。', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          btn('運転免許証', 'license'),
          const SizedBox(height: 12),
          btn('パスポート', 'passport'),
          const SizedBox(height: 12),
          btn('マイナンバーカード と 学生証', 'mynumber_student'),
          const SizedBox(height: 12),
          btn('健康保険証 と 学生証', 'insurance_student'),
        ],
      ),
    );
  }
}

class _CaptureStep extends StatelessWidget {
  final String title;
  final String? subtitle;
  final XFile? previewFile;
  final VoidCallback onBack, onRetake, onPrimary;
  final String primaryText;
  final bool isFace;

  const _CaptureStep({
    required this.title,
    this.subtitle,
    required this.previewFile,
    required this.onBack,
    required this.onRetake,
    required this.onPrimary,
    required this.primaryText,
    this.isFace = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeGreen = const Color(0xFF16C784);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left, color: Colors.white)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: const TextStyle(color: Colors.white70)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: themeGreen, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: previewFile == null
                  ? Center(
                      child: Icon(
                        isFace ? Icons.face_retouching_natural : Icons.credit_card,
                        color: themeGreen, size: 64,
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(File(previewFile!.path), fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: onRetake,
                child: const Text('もう一度撮る',
                    style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: onPrimary,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: previewFile == null ? themeGreen : Colors.white, width: 2),
                    foregroundColor: previewFile == null ? themeGreen : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    minimumSize: const Size(160, 52),
                  ),
                  child: Text(primaryText, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmitDone extends StatelessWidget {
  final VoidCallback onClose;
  const _SubmitDone({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Text('身分証・顔写真の提出を\n受け付けました',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('確認のために送信されました。',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const Spacer(),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text('完了', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPermissionInfo extends StatelessWidget {
  final VoidCallback onNext, onBack;
  const _CameraPermissionInfo({required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('カメラへのアクセスを\n許可してください。',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('次のステップで権限ダイアログが表示されます。', style: TextStyle(color: Colors.white70)),
          const Spacer(),
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: onNext,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF16C784), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                foregroundColor: const Color(0xFF16C784),
              ),
              child: const Text('写真を撮る', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineCameraPage extends StatefulWidget {
  final CameraDescription description;
  const _InlineCameraPage({required this.description});

  @override
  State<_InlineCameraPage> createState() => _InlineCameraPageState();
}

class _InlineCameraPageState extends State<_InlineCameraPage> {
  late CameraController _ctrl;
  bool _ready = false;
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = CameraController(
      widget.description,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeWithTimeout();
  }

  Future<void> _initializeWithTimeout() async {
    try {
      // 初期化が詰まる端末向けにタイムアウト
      await _ctrl.initialize().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _ready = true);
    } on TimeoutException {
      // 一度作り直す（実機でのハング明けに効く）
      try { await _ctrl.dispose(); } catch (_) {}
      _ctrl = CameraController(widget.description, ResolutionPreset.low, enableAudio: false);
      try {
        await _ctrl.initialize().timeout(const Duration(seconds: 8));
        if (!mounted) return;
        setState(() => _ready = true);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カメラの初期化に失敗しました。')),
        );
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初期化エラー: $e')),
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _onShutter() async {
    if (_shooting || !_ready || _ctrl.value.isTakingPicture) return;
    setState(() => _shooting = true);
    try {
      // プレビューを一旦止めて再開（iOS での固着回避に効果あり）
      try { await _ctrl.pausePreview(); } catch (_) {}
      try { await _ctrl.resumePreview(); } catch (_) {}

      final file = await _ctrl.takePicture().timeout(const Duration(seconds: 8));
      if (!mounted) return;

      // ★ pop は次フレームで（直後の dispose 競合を避ける）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop<XFile>(file);
      });
    } on TimeoutException {
      if (!mounted) return;
      // 撮影が詰まった場合はコントローラを作り直す
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撮影がタイムアウトしました。再初期化します…')),
      );
      try { await _ctrl.dispose(); } catch (_) {}
      _ctrl = CameraController(widget.description, ResolutionPreset.low, enableAudio: false);
      await _initializeWithTimeout();
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撮影に失敗しました: ${e.code}')),
      );
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _ready ? CameraPreview(_ctrl)
                          : const Center(child: CircularProgressIndicator()),
          ),
          // 緑フレーム等はそのまま…
          Positioned(
            top: 16, left: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _shooting ? null : _onShutter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 78, height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _shooting ? Colors.white54 : Colors.white, width: 6,
                    ),
                  ),
                  child: Center(
                    child: _shooting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
                      : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomTintPanel extends StatelessWidget {
  final Color color;
  final double height;
  const _BottomTintPanel({required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    // “ボトムナビ直上”に合わせる（必要なら調整）
    final bottomOffset = kBottomNavigationBarHeight + bottomSafe - 8;

    return IgnorePointer(
      ignoring: true, // タップは背面に通す
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomOffset),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: height,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      color.withOpacity(0.78),
                      color.withOpacity(0.46),
                      color.withOpacity(0.14),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerImage extends StatelessWidget {
  final String assetPath;
  const _BannerImage({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 24; // 左右12px余白
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _UserActionsMenuButton extends StatelessWidget {
  final VoidCallback onTap;
  const _UserActionsMenuButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'その他',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40, height: 40, // 最低タップ領域（48でもOK）
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(Icons.more_vert, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _MessageLikeSheet extends StatefulWidget {
  const _MessageLikeSheet({Key? key}) : super(key: key);

  @override
  State<_MessageLikeSheet> createState() => _MessageLikeSheetState();
}

class _MessageLikeSheetState extends State<_MessageLikeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose(); // ← 逆アニメ完了後に確実に破棄される
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('メッセージを入力してください')));
      return;
    }
    FocusScope.of(context).unfocus();   // キーボード閉じ
    Navigator.pop(context, text);       // 親へ返す（親は dispose しない）
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('メッセージを送信',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 1000,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'はじめまして！',
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                counterStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _submit,
                    child: const Text('送信する', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 受信Likeの軽量モデル
class _ReceivedLike {
  final String senderId; // 相手の user_id
  final int type;        // 0=通常,1=スーパー,2=ごちそう,3=メッセージ
  final String? message; // メッセージLike本文
  _ReceivedLike({required this.senderId, required this.type, this.message});
}

// 状態（Map と “表示済み”メモ）
final Map<String, _ReceivedLike> _receivedLikes = {};  // key = senderId
bool _loadingReceivedLikes = false;

class _MessageLikeOverlayCard extends StatefulWidget {
  final String text;
  final VoidCallback onDone;
  const _MessageLikeOverlayCard({required this.text, required this.onDone});

  @override
  State<_MessageLikeOverlayCard> createState() => _MessageLikeOverlayCardState();
}

class _MessageLikeOverlayCardState extends State<_MessageLikeOverlayCard> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => setState(() => _opacity = 1));
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _opacity = 0);
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 280),
      child: Material(
        color: Colors.black.withOpacity(0.45),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF232323), Color(0xFF0F0F0F)],
              ),
              border: Border.all(color: Colors.white12, width: 1),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Icon(Icons.message, color: Colors.pinkAccent, size: 22),
                  SizedBox(width: 8),
                  Text('メッセージLike', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                Text(
                  widget.text,
                  textAlign: TextAlign.center, // ★ 真ん中表示
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 6, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}