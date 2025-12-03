import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'user_profile_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'point_exchange_screen.dart'; // ★ 追加：ポイント画面

class AreaSelectionScreen extends StatefulWidget {
  final String userId;

  const AreaSelectionScreen({super.key, required this.userId});

  @override
  State<AreaSelectionScreen> createState() => _AreaSelectionScreenState();
}

class _AreaSelectionScreenState extends State<AreaSelectionScreen> {
  List<String> selectedAreas = [];
  double _sw(BuildContext c) => MediaQuery.of(c).size.width;
  double _sh(BuildContext c) => MediaQuery.of(c).size.height;

  /// 画面幅を 390 基準でスケール（iPhone 12/13/14 の論理解像度目安）
  double _rs(BuildContext c, double size, {double min = 10, double max = 28}) {
    final s = size * (_sw(c) / 390.0);
    return s.clamp(min, max);
  }

  final List<Map<String, String>> areaList = [
    {'name': '池袋', 'en': 'Ikebukuro', 'asset': 'assets/ikebukuro.jpg'},
    {'name': '新宿', 'en': 'Shinjuku', 'asset': 'assets/shinjuku.jpg'},
    {'name': '渋谷', 'en': 'Shibuya', 'asset': 'assets/shibuya.jpg'},
    {'name': '横浜', 'en': 'Yokohama', 'asset': 'assets/yokohama.jpg'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchSelectedAreas();
  }

  Future<void> _fetchSelectedAreas() async {
    final url = Uri.parse('https://settee.jp/user-profile/${widget.userId}/areas/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        selectedAreas = List<String>.from(data['selected_area'] ?? []);
      });
    }
  }

  Future<void> _submitSelectedAreas() async {
    final url = Uri.parse('https://settee.jp/user-profile/${widget.userId}/update-areas/');
    final body = jsonEncode({'selected_area': selectedAreas});
    await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
    Navigator.pop(context);
  }

  Widget _buildAreaTile(Map<String, String> area) {
    final bool isSelected = selectedAreas.contains(area['name']);
    return LayoutBuilder(
      builder: (context, constraints) {
        // タイルの高さは横幅に追従（3.6:1）。最小110、最大180にクランプ。
        final w = _sw(context) - 32; // 左右余白想定（後述のパディングと整合）
        final targetH = (w / 3.6).clamp(110.0, 180.0);

        final titleSize = _rs(context, 18, min: 16, max: 24);
        final subSize   = _rs(context, 12, min: 11, max: 16);
        final checkSize = _rs(context, 24, min: 20, max: 28);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: targetH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左半分に画像（常に 50% 幅）
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1.0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft:  Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      child: Image.asset(
                        area['asset']!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
              ),

              // 全面グラデーション（左→右）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.38, 0.58, 1.0], // タイル比に合わせて調整
                    ),
                  ),
                ),
              ),

              // テキスト（右側中央寄せ）
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0.55, 0.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: w * 0.38), // 右側のテキスト領域
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          area['name']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          area['en']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: subSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // チェックマーク（右端・垂直中央）
              if (isSelected)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.check_circle, color: Colors.white, size: checkSize),
                    ),
                  ),
                ),

              // インク反応（アクセシビリティ的に十分なタップ領域）
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          selectedAreas.remove(area['name']);
                        } else {
                          selectedAreas.add(area['name']!);
                        }
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // スライド遷移（左右アニメ）
  Route<T> _slideRoute<T>(Widget page, {AxisDirection direction = AxisDirection.left}) {
    Offset begin;
    switch (direction) {
      case AxisDirection.left:  begin = const Offset(1.0, 0.0);  break; // → から入る
      case AxisDirection.right: begin = const Offset(-1.0, 0.0); break; // ← から入る
      case AxisDirection.up:    begin = const Offset(0.0, 1.0);  break;
      case AxisDirection.down:  begin = const Offset(0.0, -1.0); break;
    }
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) {
        final tween = Tween(begin: begin, end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: anim.drive(tween), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final headlineSize = _rs(context, 14, min: 12, max: 16);
    final ctaHeight    = (_rs(context, 50, min: 44, max: 56)).toDouble();

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          const threshold = 150.0;
          final v = details.primaryVelocity ?? 0.0;

          if (v > threshold) {
            // 左→右：ポイント画面へ（現状のままでOK）
            Navigator.of(context).push(
              _slideRoute(
                PointExchangeScreen(userId: widget.userId),
                direction: AxisDirection.right,
              ),
            );
          } else if (v < -threshold) {
            // 右→左：常にメイン画面へ（←ここを変更）
            Navigator.of(context).pushAndRemoveUntil(
              _slideRoute(
                ProfileBrowseScreen(currentUserId: widget.userId),
                direction: AxisDirection.left, // 右からスライドイン
              ),
              (route) => false, // スタックを全破棄して強制的にメインへ
            );
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Colors.white, Color(0xFFEEEEEE), Colors.black],
              stops: [0.0, 0.7, 1.0],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              'あなたがマッチしたいエリアを選ぼう。\n新たな出会いを',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: headlineSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 36),

                            // リストは shrinkWrap で外側スクロールに委ねる
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: areaList.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 4),
                              itemBuilder: (_, i) => _buildAreaTile(areaList[i]),
                            ),

                            // 決定ボタン（中央寄せブロックの一部）
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              child: SizedBox(
                                width: double.infinity,
                                height: ctaHeight,
                                child: ElevatedButton(
                                  onPressed: _submitSelectedAreas,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    '決定する',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Route<T> _noAnimRoute<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
    maintainState: false,
    opaque: true,
  );

  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      height: 60,
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
                _noAnimRoute(ProfileBrowseScreen(currentUserId: widget.userId)),
                (route) => false,
              );
            },
            child: const Icon(Icons.home, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(DiscoveryScreen(userId: widget.userId)),
                (route) => false,
              );
            },
            child: const Icon(Icons.search, color: Colors.black),
          ),
          Image.asset('assets/logo_text.png', width: 70),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(MatchedUsersScreen(userId: widget.userId)),
                (route) => false,
              );
            },
            child: const Icon(Icons.mail_outline, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(UserProfileScreen(userId: widget.userId)),
                (route) => false,
              );
            },
            child: const Icon(Icons.person_outline, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
