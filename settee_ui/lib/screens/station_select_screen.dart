import 'package:flutter/material.dart';
import 'dart:io';
import 'match_count_screen.dart';

// ===== スケール用ヘルパー =====
double _sw(BuildContext c) => MediaQuery.of(c).size.width;
double _rs(BuildContext c, double size, {double min = 10, double max = 28}) {
  final s = size * (_sw(c) / 390.0); // 390を基準(iphone 12/13/14)
  return s.clamp(min, max);
}

class StationSelectScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String gender;
  final String birthDate;
  final String nickname;
  final String userId;
  final String password;
  final File? selectedImage;
  final File? subImage;

  const StationSelectScreen({
    super.key,
    required this.phone,
    required this.email,
    required this.gender,
    required this.birthDate,
    required this.nickname,
    required this.userId,
    required this.password,
    required this.selectedImage,
    required this.subImage,
  });

  @override
  State<StationSelectScreen> createState() => _StationSelectScreenState();
}

class _StationSelectScreenState extends State<StationSelectScreen> {
  final Set<String> _selectedAreas = {};

  final List<Map<String, String>> areaList = const [
    {'name': '池袋', 'en': 'Ikebukuro', 'asset': 'assets/ikebukuro.jpg'},
    {'name': '新宿', 'en': 'Shinjuku',  'asset': 'assets/shinjuku.jpg'},
    {'name': '渋谷', 'en': 'Shibuya',   'asset': 'assets/shibuya.jpg'},
    {'name': '横浜', 'en': 'Yokohama',  'asset': 'assets/yokohama.jpg'},
  ];

  void _onNextPressed() {
    if (_selectedAreas.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MatchCountScreen(
          phone: widget.phone,
          email: widget.email,
          gender: widget.gender,
          birthDate: widget.birthDate,
          nickname: widget.nickname,
          userId: widget.userId,
          password: widget.password,
          selectedImage: widget.selectedImage,
          subImage: widget.subImage,
          selectedAreas: _selectedAreas.toList(),
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Widget _buildAreaTile(Map<String, String> area) {
    final bool isSelected = _selectedAreas.contains(area['name']);
    return LayoutBuilder(
      builder: (context, constraints) {
        // タイル高さ：横幅に比例（3.6:1）、最小110/最大180にクランプ
        final w = _sw(context) - 32; // 左右16px余白と整合
        final h = (w / 3.6).clamp(110.0, 180.0);

        final titleSize = _rs(context, 18, min: 16, max: 24);
        final subSize   = _rs(context, 12, min: 11, max: 16);
        final checkSize = _rs(context, 24, min: 20, max: 28);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左50%を常に画像
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1.0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
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

              // 左→右グラデーション（文字の可読性確保）
              Positioned.fill(
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.38, 0.58, 1.0],
                    ),
                  ),
                ),
              ),

              // 右側テキスト
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0.55, 0.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: w * 0.38),
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

              // タップ反応（Ink効果）
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedAreas.remove(area['name']);
                        } else {
                          _selectedAreas.add(area['name']!);
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

  @override
  Widget build(BuildContext context) {
    final barHeight = (_rs(context, 4, min: 3, max: 6)).toDouble();
    final barRadius = (_rs(context, 2, min: 2, max: 3)).toDouble();
    final headlineSize = _rs(context, 14, min: 12, max: 16);
    final ctaHeight = (_rs(context, 50, min: 44, max: 56)).toDouble();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Colors.white, Color(0xFFEEEEEE), Colors.black],
            stops: [0.0, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),

                // 進捗バー（8分割のうち7まで進行の想定）
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: List.generate(8, (index) {
                      final color = index <= 6 ? const Color(0xFF16C784) : Colors.black;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(barRadius),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // 見出し
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'あなたがマッチしたいエリアを選ぼう。\n新たな出会いを',
                      style: TextStyle(color: Colors.black, fontSize: headlineSize, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // スクロール領域（タイル一覧）
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    itemCount: areaList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) => _buildAreaTile(areaList[i]),
                  ),
                ),

                // CTA
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: ctaHeight,
                    child: ElevatedButton(
                      onPressed: _selectedAreas.isNotEmpty ? _onNextPressed : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedAreas.isNotEmpty ? Colors.white : Colors.grey.shade400,
                        foregroundColor: Colors.black,
                        disabledForegroundColor: Colors.black.withOpacity(0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('次へ', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
