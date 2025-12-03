import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'welcome_screen.dart';
import 'profile_browse_screen.dart';
import 'admin_screen.dart';

/// スプラッシュ：
/// - 少なくとも2秒表示
/// - SharedPreferences から user_id を読み出し
/// - user_id が 'settee-admin' の場合は、保存済みの管理トークンが有効かも確認
///   - 有効: AdminScreen
///   - 無効: ProfileBrowseScreen（通常画面にフォールバック）
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final VideoPlayerController _videoController;
  late final Future<void> _videoInitFuture;
  late final VoidCallback _videoListener;
  Widget? _nextScreen;
  bool _videoCompleted = false;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    // 初回フレーム描画後に遷移ロジック開始（Inherited参照の競合を避ける）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  void _initializeVideo() {
    _videoController = VideoPlayerController.asset('assets/logo.mp4');
    _videoListener = () {
      if (_videoCompleted) return;
      final value = _videoController.value;
      final duration = value.duration;
      if (value.isInitialized &&
          duration != null &&
          value.position >= duration &&
          !value.isPlaying) {
        _markVideoComplete();
      }
    };
    _videoController.addListener(_videoListener);

    _videoInitFuture = _videoController.initialize().then((_) async {
      try {
        await _videoController.setLooping(false);
        await _videoController.play();
        if (mounted) {
          setState(() {});
        }
      } catch (_) {
        _markVideoComplete();
      }
    }).catchError((_) {
      _markVideoComplete();
    });
  }

  Future<void> _checkLoginStatus() async {
    try {
      // 2秒待機 & Prefs取得（Prefsは最大3秒待ち）
      final delay = Future.delayed(const Duration(seconds: 2));
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final storedUserId = prefs.getString('user_id');

      await delay; // 少なくとも2秒は表示

      if (!mounted) return;

      // 遷移先判定
      Widget next;

      if (storedUserId != null && storedUserId.isNotEmpty) {
        if (storedUserId == 'settee-admin' && _hasValidAdminToken(prefs)) {
          // 管理者ID かつ 短命トークンがまだ有効
          next = AdminScreen(currentUserId: storedUserId);
        } else {
          // 一般 or 管理トークン失効時は通常画面へ
          next = ProfileBrowseScreen(currentUserId: storedUserId);
        }
      } else {
        // 未ログイン
        next = const WelcomeScreen();
      }

      _setNextScreen(next);
    } on TimeoutException {
      // Prefs 取得が遅い環境でも起動を止めない
      if (!mounted) return;
      _setNextScreen(const WelcomeScreen());
    } catch (_) {
      // 何か起きても安全側へ
      if (!mounted) return;
      _setNextScreen(const WelcomeScreen());
    }
  }

  /// 保存済みの管理トークンが有効か判定
  /// - 'admin_access' にトークン本文
  /// - 'admin_exp' に有効期限(ミリ秒SinceEpoch)
  bool _hasValidAdminToken(SharedPreferences prefs) {
    final tok = prefs.getString('admin_access');
    final expMs = prefs.getInt('admin_exp') ?? 0;
    if (tok == null || tok.isEmpty) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return expMs > nowMs;
  }

  void _goNext(Widget next) {
    // microtask 経由で安全に遷移
    Future.microtask(() {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => next),
      );
    });
  }

  void _setNextScreen(Widget next) {
    _nextScreen = next;
    _maybeNavigate();
  }

  void _maybeNavigate() {
    if (_didNavigate || _nextScreen == null || !_videoCompleted) return;
    _didNavigate = true;
    _goNext(_nextScreen!);
  }

  void _markVideoComplete() {
    if (_videoCompleted) return;
    _videoCompleted = true;
    _maybeNavigate();
  }

  @override
  void dispose() {
    _videoController.removeListener(_videoListener);
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final videoWidth = screenWidth * 0.6; // 画面幅の60%に設定

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FutureBuilder<void>(
          future: _videoInitFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                _videoController.value.isInitialized) {
              return SizedBox(
                width: videoWidth,
                child: AspectRatio(
                  aspectRatio: _videoController.value.aspectRatio,
                  child: VideoPlayer(_videoController),
                ),
              );
            }
            if (snapshot.hasError) {
              return Image.asset(
                'assets/logo.png',
                width: 200,
                height: 200,
              );
            }
            return const CircularProgressIndicator(
              color: Colors.white,
            );
          },
        ),
      ),
    );
  }
}
