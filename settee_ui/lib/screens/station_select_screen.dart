import 'package:flutter/material.dart';
import 'dart:io';
import 'match_count_screen.dart';

class StationSelectScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String gender;
  final String birthDate;
  final String nickname;
  final String userId;
  final String password;
  final File? selectedImage;

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
  });

  @override
  State<StationSelectScreen> createState() => _StationSelectScreenState();
}

class _StationSelectScreenState extends State<StationSelectScreen> {
  final Set<String> _selectedAreas = {};

  final List<Map<String, String>> areaList = [
    {'name': '池袋', 'en': 'Ikebukuro', 'asset': 'assets/ikebukuro.jpg'},
    {'name': '新宿', 'en': 'Shinjuku', 'asset': 'assets/shinjuku.jpg'},
    {'name': '渋谷', 'en': 'Shibuya', 'asset': 'assets/shibuya.jpg'},
    {'name': '横浜', 'en': 'Yokohama', 'asset': 'assets/yokohama.jpg'},
  ];

  void _onNextPressed() {
    if (_selectedAreas.isNotEmpty) {
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
            selectedAreas: _selectedAreas.toList(),
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  Widget _buildAreaTile(Map<String, String> area) {
    final bool isSelected = _selectedAreas.contains(area['name']);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedAreas.remove(area['name']);
          } else {
            _selectedAreas.add(area['name']!);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 200,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: AssetImage(area['asset']!),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                  ],
                  stops: [0.3, 0.5, 1.0],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0.2, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    area['name']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    area['en']!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Positioned(
                right: 16,
                top: 16,
                child: Icon(Icons.check_circle, color: Colors.white, size: 24),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: List.generate(8, (index) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 4,
                          decoration: BoxDecoration(
                            color: index <= 6 ? Colors.green : Colors.black,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'あなたがマッチしたいエリアを選ぼう。\n新たな出会いを',
                      style: const TextStyle(color: Colors.black, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                ...areaList.map(_buildAreaTile).toList(),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: _selectedAreas.isNotEmpty ? _onNextPressed : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedAreas.isNotEmpty ? Colors.white : Colors.grey,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('次へ', style: TextStyle(fontWeight: FontWeight.bold)),
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
