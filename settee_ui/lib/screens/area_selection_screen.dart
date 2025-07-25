import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'user_profile_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';

class AreaSelectionScreen extends StatefulWidget {
  final String userId;

  const AreaSelectionScreen({super.key, required this.userId});

  @override
  State<AreaSelectionScreen> createState() => _AreaSelectionScreenState();
}

class _AreaSelectionScreenState extends State<AreaSelectionScreen> {
  List<String> selectedAreas = [];
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
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedAreas.remove(area['name']);
          } else {
            selectedAreas.add(area['name']!);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black, // 背景色を適当に設定
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // オーバーレイ画像
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 200,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16), // ← 角丸指定
                  image: DecorationImage(
                    image: AssetImage(area['asset']!),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),

            // グラデーション
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

            // テキスト（中央）
            Align(
              alignment: const Alignment(0.2, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
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

            // チェックマーク
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
          child: Column(
            children: [
              _buildTopNavigationBar(context),
              const SizedBox(height: 16),
              const Text(
                'あなたがマッチしたいエリアを選ぼう。\n新たな出会いを',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...areaList.map(_buildAreaTile).toList(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 35,
                  child: ElevatedButton(
                    onPressed: _submitSelectedAreas,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('決定する'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildTopNavigationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade800, width: 4),
            ),
            child: const Center(
              child: Icon(Icons.local_parking, color: Colors.white, size: 12),
            ),
          ),
          const Icon(Icons.pin_drop, color: Colors.black),
          const Icon(Icons.group, color: Colors.black),
          const Icon(Icons.person, color: Colors.black),
          const Icon(Icons.tune_rounded, color: Colors.black),
        ],
      ),
    );
  }

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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileBrowseScreen(currentUserId: widget.userId)),
              );
            },
            child: const Icon(Icons.home_outlined, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DiscoveryScreen(userId: widget.userId)),
              );
            },
            child: const Icon(Icons.search, color: Colors.black),
          ),
          Image.asset('assets/logo_text.png', width: 70),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => MatchedUsersScreen(userId: widget.userId)),
              );
            },
            child: const Icon(Icons.send_outlined, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserProfileScreen(userId: widget.userId)),
              );
            },
            child: const Icon(Icons.person_outline, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
