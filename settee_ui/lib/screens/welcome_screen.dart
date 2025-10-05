import 'package:flutter/material.dart';
import 'consent_screen.dart';
import 'login_method_screen.dart';
import 'details_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            Image.asset('assets/logo_with_text.png', height: 100),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 15),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConsentScreen(),
                  ),
                );
              },
              child: const Text('登録'),
            ),
            const SizedBox(height: 10),
            const Text('すでにSetteeのアカウントをお持ちですか？'),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginMethodScreen(),
                  ),
                );
              },
              child: const Text(
                'ログイン',
                style: TextStyle(color: Colors.blue),
              ),
            ),
            const Spacer(),
            // 利用規約とプライバシーポリシーへの遷移リンク
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                // 詳細画面へ遷移
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DetailsScreen(),
                  ),
                );
              },
              child: const Text(
                '利用規約とプライバシーポリシーを見る',
                style: TextStyle(color: Colors.blue),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
