// lib/paywall_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // 将来の購入API想定（未使用）
import 'user_profile_screen.dart';
import 'profile_browse_screen.dart';
import 'matched_users_screen.dart';
import 'cancellation_info_screen.dart'; // ← 追加

class PaywallScreen extends StatefulWidget {
  final String userId;
  final bool campaignActive;
  final String currentTier; // 'free' | 'plus' | 'vip' を想定

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

  // 列色（“現在プラン”の列を全面着色するためのカラーパレット）
  Color get _freeCol   => const Color(0xFF3C3C3C).withOpacity(0.28);
  Color get _plusCol   => const Color(0xFF2D63FF).withOpacity(0.26);
  Color get _vipCol    => const Color(0xFFFFB72C).withOpacity(0.24);
  Color get _tableEdge => Colors.white.withOpacity(0.10);

  bool get _isFree => widget.currentTier == 'free';
  bool get _isPlus => widget.currentTier == 'plus';
  bool get _isVip  => widget.currentTier == 'vip';

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
                cta: () => _onPurchase(tier: 'plus', term: _plusTerm),
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
                cta: () => _onPurchase(tier: 'vip', term: _vipTerm),
              ),

              const SizedBox(height: 28),
              _comparisonTablePremium(),
              const SizedBox(height: 18),

              // 解約方法まとめ（IAP）にワンタップで遷移
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

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
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
        // 右上からでも解約方法に飛べる導線
        IconButton(
          tooltip: '解約・更新の方法',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CancellationInfoScreen()),
            );
          },
          icon: const Icon(Icons.help_outline),
        ),
      ],
    );
  }

  Widget _headline() {
    return const Text(
      'アップグレードで、\n出会いをもっとスマートに。',
      style: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.25,
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

  // 価格セレクタ（キャンペーンの取り消し線表示込み）
  Widget _priceSelector({
    required bool isVIP,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    final items = isVIP
        ? [
            _PriceItem('1m', baseTotal: 2400, campTotal: 1980, label: "1ヶ月"),
            _PriceItem('3m', baseTotal: 5400, campTotal: 4800, label: "3ヶ月 (¥1,600/月)"),
            _PriceItem('6m', baseTotal: 7920, campTotal: 7200, label: "6ヶ月 (¥1,200/月)"),
          ]
        : [
            _PriceItem('1m', baseTotal: 890, campTotal: 580, label: "1ヶ月"),
            _PriceItem('3m', baseTotal: 2010, campTotal: 1500, label: "3ヶ月 (¥500/月)"),
            _PriceItem('6m', baseTotal: 2940, campTotal: 2400, label: "6ヶ月 (¥400/月)"),
          ];

    const double _kPriceTileMinHeight = 120;

    return Column(
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
    required VoidCallback cta,
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

  // ======= 現在プランの“列”だけを一枚背景でつなげて強調（凡例はStack外） =======
  Widget _comparisonTablePremium() {
    // ✓/×（free / plus / vip）
    final features = <Map<String, dynamic>>[
      {'name': 'Like無制限',             'vals': [false, true,  true ]},
      {'name': 'Super Like',            'vals': [false, false, true ]},
      {'name': '戻る機能',               'vals': [false, false, true ]},
      {'name': 'ごちそう Like',          'vals':[false, false, true ]},
      {'name': 'メッセージ Like',        'vals':[false,false, true ]},
      {'name': 'マッチングブースト',       'vals':[false, false, true ]},
      {'name': 'プライベートモード',       'vals':[false, true,  true ]},
    ];

    // 現在列（1=通常/2=Plus/3=VIP）
    final int activeCol = _isVip ? 3 : _isPlus ? 2 : 1;

    // 背景色（現在列のみ使用）
    Color activeColColor(int colIndex) {
      if (colIndex == 1 && _isFree) return _freeCol;
      if (colIndex == 2 && _isPlus) return _plusCol;
      if (colIndex == 3 && _isVip)  return _vipCol;
      return Colors.transparent;
    }

    // レイアウト定数（ヘッダ先頭に背景を合わせたい）
    const double gap = 8.0;        // 列間
    const double headerH = 44.0;   // ヘッダ高さ
    const double headerSpacer = 8; // ヘッダと行の間
    const double rowH = 46.0;      // 各行の高さ
    const double rowGap = 10.0;    // 各行の縦間隔（Padding vertical:5 の合計）
    final int rowCount = features.length;

    final TextStyle headerStyle = TextStyle(
      color: Colors.white.withOpacity(0.95),
      fontWeight: FontWeight.w900,
      fontSize: 13,
      letterSpacing: 0.2,
    );

    Widget headCell(String label) => SizedBox(
          height: headerH,
          child: Center(child: Text(label, style: headerStyle)),
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
          // ▼ 凡例は Stack の外（＝背景の計算対象から除外）
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

          // ▼ ここからヘッダ＋行のみを Stack で重ね、背景をヘッダ先頭に揃える
          LayoutBuilder(
            builder: (context, constraints) {
              final double w = constraints.maxWidth;

              // flex: 5 | 3 | 3 | 3、列間gapは2箇所
              final double contentW = w - (gap * 2);
              const int totalFlex = 14; // 5+3+3+3
              final double labelW = contentW * 5 / totalFlex;
              final double colW   = contentW * 3 / totalFlex;

              // 各列の左端座標（コンテンツ左端からのオフセット）
              final double col1Left = labelW;                  // 通常
              final double col2Left = labelW + colW + gap;     // Plus
              final double col3Left = labelW + colW*2 + gap*2; // VIP
              final double activeLeft = (activeCol == 1) ? col1Left
                                    : (activeCol == 2) ? col2Left : col3Left;

              // 背景サイズ（ヘッダ～最終行までを1枚で覆う）
              final double totalHeight =
                  headerH + headerSpacer + rowCount * rowH + (rowCount - 1) * rowGap;

              return Stack(
                children: [
                  // ▼ 背景（現在列のみ色付き）
                  Positioned(
                    left: activeLeft,
                    top: 0,                 // ← 凡例を外に出したので0でOK（ヘッダ先頭）
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

                  // ▼ 実データ（ヘッダ＋行）
                  Column(
                    children: [
                      // ヘッダ
                      Row(
                        children: const [
                          Expanded(flex: 5, child: SizedBox()),
                          Expanded(flex: 3, child: SizedBox(height: headerH, child: Center(child: Text("通常")))),
                          SizedBox(width: gap),
                          Expanded(flex: 3, child: SizedBox(height: headerH, child: Center(child: Text("Plus")))),
                          SizedBox(width: gap),
                          Expanded(flex: 3, child: SizedBox(height: headerH, child: Center(child: Text("VIP")))),
                        ],
                      ),
                      const SizedBox(height: headerSpacer),

                      // 値行
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

  void _onPurchase({required String tier, required String term}) {
    // TODO: 実際の IAP 実装と連携
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('未実装: $tier / $term の購入処理')),
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
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => ProfileBrowseScreen(currentUserId: userId)));
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
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => MatchedUsersScreen(userId: userId)));
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.mail_outline, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
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
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
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

// 価格アイテム
class _PriceItem {
  final String key;      // '1m', '3m', '6m'
  final int baseTotal;   // 合計金額
  final int campTotal;   // キャンペーン価格
  final String label;    // 表示用
  _PriceItem(this.key, {required this.baseTotal, required this.campTotal, required this.label});
}
