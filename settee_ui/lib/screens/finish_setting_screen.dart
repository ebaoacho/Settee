import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_browse_screen.dart';

class FinalSettingScreen extends StatefulWidget {
  final String userId;

  const FinalSettingScreen({super.key, required this.userId});

  @override
  State<FinalSettingScreen> createState() => _FinalSettingScreenState();
}

class _FinalSettingScreenState extends State<FinalSettingScreen> {
  @override
  void initState() {
    super.initState();

    // 自動ログイン情報の保存
    _storeUserId();

    // 3秒後に次の画面へ遷移
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProfileBrowseScreen(
            currentUserId: widget.userId,
            showTutorial: true,
          ),
        ),
      );
    });
  }

  Future<void> _storeUserId() async {
    final prefs = await SharedPreferences.getInstance();

    // 自動ログイン用の user_id を保存
    await prefs.setString('user_id', widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: List.generate(8, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const Spacer(),
            Center(
              child: Image.asset(
                'assets/check_star.png',
                width: 520,
                height: 520,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
