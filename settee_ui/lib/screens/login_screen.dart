import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'admin_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    final loginInput = _loginController.text.trim();
    final passwordInput = _pwController.text.trim();

    if (loginInput.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID（またはメール）とパスワードを入力してください')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final url = Uri.parse('https://settee.jp/login/');

    try {
      // 1) 通常ログイン
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': loginInput,
          'password': passwordInput,
        }),
      );

      if (!mounted) return; // await 後の最初の mounted チェック

      if (response.statusCode == 200) {
        final bodyString = utf8.decode(response.bodyBytes);
        final data = jsonDecode(bodyString) as Map<String, dynamic>;

        final userId = data['user_id'] as String;

        // 2) 端末に通常の user_id を保存
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', userId);

        // 成功トースト
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'ログインに成功しました')),
        );

        // 3) 管理者なら、ログイン直後に“サイレント昇格”（短命トークン取得）
        String? adminToken;
        int? adminExpMs;
        if (userId == 'settee-admin') {
          try {
            final adminRes = await http.post(
              Uri.parse('https://settee.jp/admin/simple-token/'),
              headers: {'Content-Type': 'application/json'},
              // サーバ側は Django 認証ユーザ（auth_user）の username/password を検証
              body: jsonEncode({'username': userId, 'password': passwordInput}),
            );

            if (adminRes.statusCode == 200) {
              final m = jsonDecode(utf8.decode(adminRes.bodyBytes)) as Map<String, dynamic>;
              adminToken = (m['access'] as String?)?.trim();
              final ttlSec = (m['expires_in'] as num?)?.toInt() ?? 900;
              adminExpMs = DateTime.now().millisecondsSinceEpoch + ttlSec * 1000;

              if (adminToken != null && adminToken!.isNotEmpty) {
                await prefs.setString('admin_access', adminToken!);
                await prefs.setInt('admin_exp', adminExpMs);
              }
            } else {
              // 失敗しても通常ログイン自体は成功なので、デバッグ出力のみに留める
              debugPrint('admin token issue failed: ${adminRes.statusCode} ${adminRes.body}');
            }
          } catch (e) {
            debugPrint('admin token error: $e');
          }
        }

        if (!mounted) return;

        // 4) 管理トークンが有効なら Admin、なければ通常画面へ
        final savedTok = (await SharedPreferences.getInstance()).getString('admin_access');
        final savedExp = (await SharedPreferences.getInstance()).getInt('admin_exp') ?? 0;
        final hasAdminToken =
            (userId == 'settee-admin') && savedTok != null && savedTok.isNotEmpty && savedExp > DateTime.now().millisecondsSinceEpoch;

        final Widget next = hasAdminToken
            ? AdminScreen(currentUserId: userId)
            : ProfileBrowseScreen(currentUserId: userId, showTutorial: false);

        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['detail']?.toString() ?? 'ログインに失敗しました')),
        );
      }
    } catch (e) {
      if (!mounted) return; // 例外後の mounted チェック
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信エラーが発生しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey[900],
      labelStyle: const TextStyle(color: Colors.white70),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.greenAccent, width: 1),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              // 戻るボタン
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              const SizedBox(height: 40),
              const Text('ログイン',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),

              // ID / メール
              TextField(
                controller: _loginController,
                style: const TextStyle(color: Colors.white),
                decoration: inputDecoration.copyWith(labelText: 'ID または メールアドレス'),
              ),
              const SizedBox(height: 24),

              // パスワード
              TextField(
                controller: _pwController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: inputDecoration.copyWith(labelText: 'パスワード'),
              ),
              const SizedBox(height: 32),

              // ログインボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('ログイン'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
