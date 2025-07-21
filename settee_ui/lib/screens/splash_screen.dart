import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'profile_browse_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUserId = prefs.getString('user_id');

    // 2秒間スプラッシュ画面を表示
    await Future.delayed(const Duration(seconds: 2));

    if (storedUserId != null) {
      // 自動ログイン成功 → プロフィール閲覧画面へ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProfileBrowseScreen(currentUserId: storedUserId),
        ),
      );
    } else {
      // 通常ログイン画面へ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          'assets/logo.png',
          width: 200,
          height: 200,
        ),
      ),
    );
  }
}
