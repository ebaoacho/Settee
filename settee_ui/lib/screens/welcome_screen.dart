import 'package:flutter/material.dart';
import 'signup_method_screen.dart';
import 'login_method_screen.dart';

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
                    builder: (context) => const SignUpMethodScreen(),
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
            const Text('利用規約 と プライバシーポリシー',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
