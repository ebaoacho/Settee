// lib/paywall_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'user_profile_screen.dart';
import 'profile_browse_screen.dart';
import 'matched_users_screen.dart';
import 'cancellation_info_screen.dart';

// ====== IAP ======
const kProductIds = <String>{
  'jp.settee.app.vip.1m',
  'jp.settee.app.vip.3m',
  'jp.settee.app.vip.6m',
  'jp.settee.app.plus.1m',
  'jp.settee.app.plus.3m',
  'jp.settee.app.plus.6m',
};

const kSkuByKey = {
  'vip':  {'1m': 'jp.settee.app.vip.1m',  '3m': 'jp.settee.app.vip.3m',  '6m': 'jp.settee.app.vip.6m'},
  'plus': {'1m': 'jp.settee.app.plus.1m', '3m': 'jp.settee.app.plus.3m', '6m': 'jp.settee.app.plus.6m'},
};

// ====== API Client ======
class ApiClient {
  // 本番APIのベースURL（環境に合わせて差し替え可）
  static const String baseUrl = 'https://settee.jp';
  static Uri _u(String path) => Uri.parse('$baseUrl$path');

  // ===== debugPrint ユーティリティ =====
  static void _dp(String msg) => debugPrint('[ApiClient] $msg');

  static void _dpChunk(String label, String text, {int chunk = 800}) {
    if (text.isEmpty) {
      _dp('$label <empty>');
      return;
    }
    final total = text.length;
    int i = 0, idx = 0;
    while (i < total) {
      final end = (i + chunk < total) ? i + chunk : total;
      final piece = text.substring(i, end);
      _dp('$label [${++idx}/${(total / chunk).ceil()}] $piece');
      i = end;
    }
  }

  static String _preview(String s, {int max = 400}) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '...(${s.length} chars)';
  }

  static bool _isJsonCT(String? ct) =>
      (ct ?? '').toLowerCase().contains('application/json');

  static Map<String, dynamic> _decodeJsonOrThrow(http.Response resp, {String where = ''}) {
    final ct = resp.headers['content-type'] ?? '';
    final looksJson = _isJsonCT(ct);
    _dp('[$where] HTTP ${resp.statusCode}, content-type="$ct", len=${resp.bodyBytes.length}');
    if (!looksJson) {
      _dpChunk('[$where] Non-JSON body preview', _preview(resp.body));
      throw Exception('Non-JSON response $where (status=${resp.statusCode}, ct="$ct")');
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        // ログに一部出す（長すぎるものはプレビュー）
        _dpChunk('[$where] JSON body preview', _preview(resp.body));
        return decoded;
      }
      _dp('[$where] JSON root is not an object: ${decoded.runtimeType}');
      throw Exception('JSON root is not an object');
    } catch (e) {
      _dp('[$where] JSON parse failed: $e');
      _dpChunk('[$where] raw body preview', _preview(resp.body));
      throw Exception('JSON parse failed: $e');
    }
  }

  // ===== API =====
  static Future<Map<String, dynamic>> verifyIosReceipt({
    required String userId,
    required String receiptBase64,
    bool? forceSandbox,
  }) async {
    // JWS / Base64 の見た目をログ
    final looksJws = receiptBase64.contains('.') && receiptBase64.startsWith('eyJ');
    final looksB64 = RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(
      receiptBase64.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', ''),
    );
    final head = receiptBase64.isNotEmpty ? receiptBase64.substring(0, 40) : '';
    final tail = receiptBase64.length > 40
        ? receiptBase64.substring(receiptBase64.length - 40)
        : receiptBase64;

    _dp('[verify] user=$userId forceSandbox=$forceSandbox '
        'len=${receiptBase64.length} looksJWS=$looksJws looksB64=$looksB64');
    _dp('[verify] head="$head" ... tail="$tail"');

    final uri = _u('/iap/ios/verify/');
    _dp('[verify] POST $uri');

    final resp = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'user_id': userId,
        'receipt_data': receiptBase64,
        if (forceSandbox != null) 'force_sandbox': forceSandbox,
      }),
    );

    final bodyJson = _decodeJsonOrThrow(resp, where: 'verify');

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _dp('[verify] server returned error status ${resp.statusCode}: $bodyJson');
      throw Exception('verify failed: status=${resp.statusCode}, body=$bodyJson');
    }

    _dp('[verify] OK');
    return bodyJson;
  }

  static Future<Map<String, dynamic>> fetchEntitlements(String userId) async {
    final uri = _u('/users/$userId/entitlements/');
    _dp('[entitlements] GET $uri');

    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    final bodyJson = _decodeJsonOrThrow(resp, where: 'entitlements');

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _dp('[entitlements] server returned error status ${resp.statusCode}: $bodyJson');
      throw Exception('entitlements fetch failed: status=${resp.statusCode}, body=$bodyJson');
    }

    _dp('[entitlements] OK');
    return bodyJson;
  }
}

// ====== IAP Controller ======
class IapController {
  final _iap = InAppPurchase.instance;
  final Map<String, ProductDetails> _pd = {};

  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;
    final resp = await _iap.queryProductDetails(kProductIds);
    if (resp.error != null || resp.productDetails.isEmpty) return;
    for (final p in resp.productDetails) {
      _pd[p.id] = p;
    }
  }

  ProductDetails? product(String tier, String term) =>
      _pd[kSkuByKey[tier]![term]];

  Future<void> buy(String tier, String term, {String? appAccountToken}) async {
    final pd = product(tier, term);
    if (pd == null) throw Exception('Product not loaded: $tier/$term');

    final param = PurchaseParam(
      productDetails: pd,
      // iOS: StoreKit2 の appAccountToken にマッピングされる
      applicationUserName: appAccountToken,
    );

    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() => _iap.restorePurchases();
}

// ====== UI ======
class PaywallScreen extends StatefulWidget {
  final String userId;
  final bool campaignActive;     // リリースから1ヶ月限定キャンペーンの可否
  final String currentTier;      // 'free' | 'plus' | 'vip'

  const PaywallScreen({
    super.key,
    required this.userId,
    this.campaignActive = true,
    this.currentTier = 'free',
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  String _plusTerm = '1m';
  String _vipTerm  = '1m';

  // サーバ同期後にUIへ即反映するため、現在プランはStateで保持
  late String _currentTier; // 'free' | 'plus' | 'vip'

  // 現在プラン強調の配色
  Color get _freeCol   => const Color(0xFF3C3C3C).withOpacity(0.28);
  Color get _plusCol   => const Color(0xFF2D63FF).withOpacity(0.26);
  Color get _vipCol    => const Color(0xFFFFB72C).withOpacity(0.24);
  Color get _tableEdge => Colors.white.withOpacity(0.10);

  bool get _isFree => _currentTier == 'free';
  bool get _isPlus => _currentTier == 'plus';
  bool get _isVip  => _currentTier == 'vip';

  late final IapController iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _loadingEntitlements = false;
  bool _purchasing = false;
  final Set<String> _handled = {};       // 同一イベントの二重処理を防ぐ
  bool _showingResultDialog = false;     // ダイアログ多重表示防止

  @override
  void initState() {
    super.initState();
    _currentTier = widget.currentTier;

    iap = IapController();
    iap.init().then((_) => mounted ? setState(() {}) : null);

    // 起動時にサーバの最新権限を反映
    _refreshEntitlements(silent: true);

    // 購入ストリーム購読（disposeで解放）
    _purchaseSub = iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        // ---- 二重処理ガード（purchaseID+status 単位で一意に）----
        final key = '${p.purchaseID ?? 'none'}:${p.status}';
        if (_handled.contains(key)) continue;
        _handled.add(key);

        try {
          switch (p.status) {
            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              try {
                if (Platform.isIOS) {
                  final receipt = p.verificationData.serverVerificationData;

                  // 診断ログ（必要に応じて残す）
                  final normalized = receipt.replaceAll(RegExp(r'\s'), '');
                  final looksB64 = RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(normalized);
                  final n = normalized.length;
                  final head = normalized.substring(0, n < 32 ? n : 32);
                  final tail = normalized.substring(n < 32 ? 0 : n - 32);
                  debugPrint('[IAP] source=${p.verificationData.source} len=$n looksB64=$looksB64 '
                      'head=$head ... tail=$tail');

                  if (receipt.isNotEmpty) {
                    await ApiClient.verifyIosReceipt(
                      userId: widget.userId,
                      receiptBase64: receipt,
                    );
                  }
                }

                // サーバ反映→UI更新（静かに）
                await _refreshEntitlements(silent: true);

                // 購入/復元 完了ダイアログ（1回だけ）
                final title = (p.status == PurchaseStatus.restored)
                    ? 'データを取得しました'
                    : '購入が完了しました';
                await _showPurchaseResultDialog(
                  title: title,
                  message: '現在のプラン：${_currentPlanLabel()}',
                );
              } catch (e) {
                if (mounted) {
                  // エラー系は SnackBar 維持でOK
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('レシート検証に失敗: $e')),
                  );
                }
              }
              break;

            case PurchaseStatus.pending:
              // 表示は任意（今回は何も出さない）
              break;

            case PurchaseStatus.error:
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('購入エラー: ${p.error}')),
                );
              }
              break;

            case PurchaseStatus.canceled:
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('購入をキャンセルしました。')),
                );
              }
              break;
          }
        } finally {
          // ★ 成功・失敗・キャンセルすべてで完了させる
          if (p.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(p);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  String _currentPlanLabel() => _isVip ? 'VIP' : _isPlus ? 'Plus' : '通常';

  Future<void> _showPurchaseResultDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted || _showingResultDialog) return;
    _showingResultDialog = true;

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'result',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        transitionBuilder: (ctx, anim, _, __) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
          return Opacity(
            opacity: anim.value,
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: Center(
                child: _PrettyDialog(
                  title: title,
                  message: message,
                  planLabel: _currentPlanLabel(),
                  onManage: () {
                    Navigator.of(ctx).pop();
                    launchUrlString('itms-apps://apps.apple.com/account/subscriptions');
                  },
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _showingResultDialog = false;
    }
}

  // ユーザーIDベースで決定論的 UUIDv5 を生成（iOSのみ使用）
  String? _appAccountToken() {
    if (!Platform.isIOS) return null;
    return const Uuid().v5(Uuid.NAMESPACE_URL, 'settee:${widget.userId}');
  }

  Future<void> _refreshEntitlements({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _loadingEntitlements = true);
    try {
      final ent = await ApiClient.fetchEntitlements(widget.userId);
      final tier = (ent['tier'] as String?) ?? 'NORMAL';
      final mapped = (tier.toUpperCase() == 'VIP')
          ? 'vip'
          : (tier.toUpperCase() == 'PLUS')
              ? 'plus'
              : 'free';
      if (mounted) setState(() => _currentTier = mapped);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('権限を更新しました。')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('権限の取得に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEntitlements = false);
    }
  }

  Future<void> _onPurchase({required String tier, required String term}) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      if (Platform.isIOS) {
        // 現在の状態を最新化するための復元だけは行う
        // debugPrint('[IAP] preflight: restore first');
        await iap.restore();
        await Future.delayed(const Duration(milliseconds: 400));
        await _refreshEntitlements(silent: true);

        // ★ ここで return しないことが重要 ★
        final sameTier = (_isVip && tier == 'vip') || (_isPlus && tier == 'plus');
        if (sameTier) {
          // debugPrint('[IAP] already on $tier; presenting StoreKit change-flow via purchase()');
        } else {
          // debugPrint('[IAP] cross-tier change ($_currentTier -> $tier); presenting purchase()');
        }
      }

      // サブスクが有効でも purchase() を呼べば、同一グループ内は「変更」ダイアログが出る
      await iap.buy(tier, term, appAccountToken: _appAccountToken());
    } on PlatformException catch (e) {
      // debugPrint('[IAP] buy PlatformException code=${e.code} message=${e.message} details=${e.details}');
      if (!mounted) return;
      await _showPurchaseResultDialog(
        title: '購入を開始できませんでした',
        message: '${e.code} ${e.message ?? ""}',
      );
    } catch (e) {
      if (!mounted) return;
      await _showPurchaseResultDialog(
        title: '購入を開始できませんでした',
        message: '$e',
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _onRestore() async {
    try {
      await iap.restore();
      // restore の結果は purchaseStream に流れる → そこで検証&反映済み
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('購入情報を復元しました。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('復元に失敗しました: $e')),
      );
    }
  }

  PreferredSizeWidget _topBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      centerTitle: true,
      title: SizedBox(
        height: 28,
        child: Image.asset('assets/white_logo_text.png', width: 90),
      ),
      actions: [
        if (_loadingEntitlements)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          )
        else
          IconButton(
            tooltip: '権限を再取得',
            onPressed: _refreshEntitlements,
            icon: const Icon(Icons.refresh),
          ),
        IconButton(
          tooltip: 'サブスクリプションを管理',
          onPressed: () => launchUrlString('itms-apps://apps.apple.com/account/subscriptions'),
          icon: const Icon(Icons.manage_accounts_outlined),
        ),
        IconButton(
          tooltip: '解約・更新の方法',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CancellationInfoScreen()),
            );
          },
          icon: const Icon(Icons.info_outline),
        ),
      ],
    );
  }

  Widget _headline() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'アップグレードで、\n出会いをもっとスマートに。',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
        TextButton(
          onPressed: _onRestore,
          child: const Text('購入を復元', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _topBar(),
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.userId),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headline(),
              const SizedBox(height: 16),

              _tierCard(
                title: "Settee Plus",
                gradient: const LinearGradient(
                  colors: [Color(0xFFEFF3FF), Color(0xFFD6E0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                chromeBorder: const Color(0x33FFFFFF),
                accentDot: const Color(0xFF243B9F),
                content: _plusContent(),
                footer: _priceSelector(
                  isVIP: false,
                  selected: _plusTerm,
                  onChanged: (v) => setState(() => _plusTerm = v),
                ),
              ),

              const SizedBox(height: 22),

              _tierCard(
                title: "Settee VIP",
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF3D4), Color(0xFFF7D66B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                chromeBorder: const Color(0x66FFFFFF),
                accentDot: const Color(0xFF6B4D10),
                content: _vipContent(),
                footer: _priceSelector(
                  isVIP: true,
                  selected: _vipTerm,
                  onChanged: (v) => setState(() => _vipTerm = v),
                ),
              ),

              const SizedBox(height: 28),
              _comparisonTablePremium(),
              const SizedBox(height: 18),

              // 解約案内 & 管理画面導線
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CancellationInfoScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.28)),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  label: const Text(
                    '解約・更新の方法を確認',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrlString('itms-apps://apps.apple.com/account/subscriptions'),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.28)),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  label: const Text(
                    'サブスクリプションを管理',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ---- PLUS ----
  Widget _plusContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 10),
        _FeatureRow("Like数", "無制限", highlighted: true),
        _FeatureRow("Super Like", "オフ"),
        _FeatureRow("戻る機能", "オフ"),
        _FeatureRow("ごちそう Like", "オフ"),
        _FeatureRow("メッセージ Like", "オフ"),
        _FeatureRow("マッチングブースト", "オフ"),
        _FeatureRow("プライベートモード", "オン", highlighted: true),
      ],
    );
  }

  // ---- VIP ----
  Widget _vipContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 10),
        _FeatureRow("Like数", "無制限", highlighted: true),
        _FeatureRow("Super Like", "10回 / 月"),
        _FeatureRow("戻る機能", "オン"),
        _FeatureRow("ごちそう Like", "10回 / 月"),
        _FeatureRow("メッセージ Like", "10回 / 月"),
        _FeatureRow("マッチングブースト", "オン"),
        _FeatureRow("プライベートモード", "オン", highlighted: true),
      ],
    );
  }

  // 価格セレクタ（キャンペーンの取り消し線表示＋※注記付き）
  Widget _priceSelector({
    required bool isVIP,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    final items = isVIP
        ? [
            _PriceItem('1m', baseTotal: 2400, campTotal: 1980, label: "1ヶ月"),
            _PriceItem('3m', baseTotal: 5400, campTotal: 4800, label: "3ヶ月 (¥1,600/月)"),
            _PriceItem('6m', baseTotal: 7980, campTotal: 7200, label: "6ヶ月 (¥1,200/月)"),
          ]
        : [
            _PriceItem('1m', baseTotal: 890, campTotal: 580, label: "1ヶ月"),
            _PriceItem('3m', baseTotal: 2080, campTotal: 1500, label: "3ヶ月 (¥500/月)"),
            _PriceItem('6m', baseTotal: 2980, campTotal: 2400, label: "6ヶ月 (¥400/月)"),
          ];

    const double _kPriceTileMinHeight = 120;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: items.map((it) {
            final active = selected == it.key;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: GestureDetector(
                  onTap: () => onChanged(it.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: _kPriceTileMinHeight),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: active ? Colors.black : Colors.white.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          it.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (widget.campaignActive) ...[
                          Text(
                            "¥${it.baseTotal}",
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: active ? Colors.white70 : Colors.black54,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "¥${it.campTotal}",
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.2,
                            ),
                          ),
                        ] else ...[
                          Text(
                            "¥${it.baseTotal}",
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // ▼ 追加：タイル直下の※注記
        const SizedBox(height: 8),
        Text(
          widget.campaignActive
              ? '※ 取り消し線の部分は通常価格です。表示価格はリリースから1か月間限定のキャンペーン価格です。終了後は通常価格に自動で戻ります。'
              : '※ 表示価格は通常価格です。',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                height: 1.2,
              ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _onPurchase(tier: isVIP ? 'vip' : 'plus', term: selected),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('アップグレードする »', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  // 高級感のある“ガラス質感”カード
  Widget _tierCard({
    required String title,
    required LinearGradient gradient,
    required Color chromeBorder,
    required Color accentDot,
    required Widget content,
    required Widget footer,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: chromeBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: const SizedBox(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _dot(accentDot),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.workspace_premium, color: Colors.black87),
                    ],
                  ),
                  const SizedBox(height: 12),
                  content,
                  const SizedBox(height: 12),
                  footer,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======= 現在プラン比較テーブル =======
  Widget _comparisonTablePremium() {
    final features = <Map<String, dynamic>>[
      {'name': 'Like無制限',       'vals': [false, true,  true ]},
      {'name': 'Super Like',      'vals': [false, false, true ]},
      {'name': '戻る機能',         'vals': [false, false, true ]},
      {'name': 'ごちそう Like',    'vals': [false, false, true ]},
      {'name': 'メッセージ Like',  'vals': [false, false, true ]},
      {'name': 'マッチングブースト','vals': [false, false, true ]},
      {'name': 'プライベートモード','vals': [false, true,  true ]},
    ];

    final int activeCol = _isVip ? 3 : _isPlus ? 2 : 1;

    Color activeColColor(int colIndex) {
      if (colIndex == 1 && _isFree) return _freeCol;
      if (colIndex == 2 && _isPlus) return _plusCol;
      if (colIndex == 3 && _isVip)  return _vipCol;
      return Colors.transparent;
    }

    const double gap = 8.0;
    const double headerH = 44.0;
    const double headerSpacer = 8;
    const double rowH = 46.0;
    const double rowGap = 10.0;
    final int rowCount = features.length;

    final TextStyle headerStyle = TextStyle(
      color: Colors.white.withOpacity(0.95),
      fontWeight: FontWeight.w900,
      fontSize: 13,
      letterSpacing: 0.2,
    );

    Widget iconCell(bool enabled) => SizedBox(
          height: rowH,
          child: Center(
            child: Icon(
              enabled ? Icons.check_rounded : Icons.close_rounded,
              size: 18,
              color: Colors.white.withOpacity(0.95),
            ),
          ),
        );

    Widget nameCell(String label) => SizedBox(
          height: rowH,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _tableEdge),
        gradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '✓ = 利用可   × = 利用不可',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final double w = constraints.maxWidth;

              final double contentW = w - (gap * 2);
              const int totalFlex = 14; // 5+3+3+3
              final double labelW = contentW * 5 / totalFlex;
              final double colW   = contentW * 3 / totalFlex;

              final double col1Left = labelW;                  // 通常
              final double col2Left = labelW + colW + gap;     // Plus
              final double col3Left = labelW + colW*2 + gap*2; // VIP
              final double activeLeft = (activeCol == 1) ? col1Left
                                    : (activeCol == 2) ? col2Left : col3Left;

              final double totalHeight =
                  headerH + headerSpacer + rowCount * rowH + (rowCount - 1) * rowGap;

              return Stack(
                children: [
                  Positioned(
                    left: activeLeft,
                    top: 0,
                    width: colW,
                    height: totalHeight,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: activeColColor(activeCol),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(flex: 5, child: SizedBox()),
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: headerH,
                              child: Center(child: Text("通常", style: headerStyle)),
                            ),
                          ),
                          const SizedBox(width: gap),
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: headerH,
                              child: Center(child: Text("Plus", style: headerStyle)),
                            ),
                          ),
                          const SizedBox(width: gap),
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: headerH,
                              child: Center(child: Text("VIP", style: headerStyle)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: headerSpacer),
                      ...features.map((f) {
                        final vals = f['vals'] as List<bool>;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: (rowGap / 2)),
                          child: Row(
                            children: [
                              Expanded(flex: 5, child: nameCell(f['name'] as String)),
                              Expanded(flex: 3, child: iconCell(vals[0])),
                              const SizedBox(width: gap),
                              Expanded(flex: 3, child: iconCell(vals[1])),
                              const SizedBox(width: gap),
                              Expanded(flex: 3, child: iconCell(vals[2])),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "現在のプラン：${_isVip ? "VIP" : _isPlus ? "Plus" : "通常"}",
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Route<T> _noAnimRoute<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
    maintainState: false,
    opaque: true,
  );

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
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(ProfileBrowseScreen(currentUserId: userId)),
                (route) => false,
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.home_outlined, color: Colors.black),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 10.0),
            child: Icon(Icons.search, color: Colors.black),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Image.asset('assets/logo_text.png', width: 70),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(MatchedUsersScreen(userId: userId)),
                (route) => false,
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.mail_outline, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(UserProfileScreen(userId: userId)),
                (route) => false,
              );
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

// 表示用：カード内の1行
class _FeatureRow extends StatelessWidget {
  final String name;
  final String value;
  final bool highlighted;
  const _FeatureRow(this.name, this.value, {this.highlighted=false, super.key});

  @override
  Widget build(BuildContext context) {
    final isOff = value == "オフ";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isOff ? Icons.close_rounded : Icons.check_circle_rounded,
            size: 18,
            color: isOff ? Colors.black54 : Colors.black87,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.black87,
              fontWeight: highlighted ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// 価格アイテム（UI表示用）
class _PriceItem {
  final String key;      // '1m', '3m', '6m'
  final int baseTotal;   // 通常価格（合計）
  final int campTotal;   // キャンペーン価格（合計）
  final String label;    // 表示用
  _PriceItem(this.key, {required this.baseTotal, required this.campTotal, required this.label});
}

class _PrettyDialog extends StatelessWidget {
  final String title;
  final String message;
  final String planLabel;
  final VoidCallback onManage;
  final VoidCallback onClose;

  const _PrettyDialog({
    super.key,
    required this.title,
    required this.message,
    required this.planLabel,
    required this.onManage,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // ガラス質感
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.92),
                    Colors.white.withOpacity(0.86),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.65)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // トップのアイコン + グラデ
                  Container(
                    width: 64, height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF2D63FF), Color(0xFFFFB72C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.workspace_premium, size: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // タイトル
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // メッセージ + プランバッジ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PlanChip(label: planLabel),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ボタン2つ
                  Row(
                    children: [
                      Expanded(
                        child: _GlassButton(
                          text: 'サブスクリプションを管理',
                          onPressed: onManage,
                          filled: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GlassButton(
                          text: 'OK',
                          onPressed: onClose,
                          filled: true,
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
    );
  }
}

class _PlanChip extends StatelessWidget {
  final String label;
  const _PlanChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isVip  = label.toUpperCase() == 'VIP';
    final isPlus = label.toUpperCase() == 'PLUS';
    final colors = isVip
        ? const [Color(0xFFFFF3D4), Color(0xFFF7D66B)]
        : isPlus
            ? const [Color(0xFFEFF3FF), Color(0xFFD6E0FF)]
            : [Colors.grey.shade200, Colors.grey.shade100];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVip ? Icons.workspace_premium : Icons.star_rate_rounded,
            size: 16,
            color: Colors.black87,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool filled;
  const _GlassButton({
    required this.text,
    required this.onPressed,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        foregroundColor: filled ? Colors.white : Colors.black87,
        backgroundColor: filled ? Colors.black : Colors.white.withOpacity(0.92),
        side: BorderSide(color: filled ? Colors.black : Colors.black.withOpacity(0.10)),
        shadowColor: Colors.black.withOpacity(0.25),
        elevation: filled ? 2 : 0,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.2,
          color: filled ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
