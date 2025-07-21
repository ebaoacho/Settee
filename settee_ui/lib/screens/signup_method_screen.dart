import 'package:flutter/material.dart';
import 'input_screen.dart';

class SignUpMethodScreen extends StatelessWidget {
  const SignUpMethodScreen({super.key});

  Widget _buildSocialButton({
    required Icon icon,
    required String label,
    VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: const StadiumBorder(),
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Image.asset(
                  'assets/logo_welcome.png',
                  width: 300,
                ),
              ),
              const SizedBox(height: 40),
              // _buildSocialButton(
              //   icon: const Icon(Icons.chat),
              //   label: 'LINEで続ける',
              //   onPressed: () {},
              // ),
              // _buildSocialButton(
              //   icon: const Icon(Icons.apple),
              //   label: 'Appleで続ける',
              //   onPressed: () {},
              // ),
              // _buildSocialButton(
              //   icon: const Icon(Icons.g_mobiledata),
              //   label: 'Googleで続ける',
              //   onPressed: () {},
              // ),
              _buildSocialButton(
                icon: const Icon(Icons.phone),
                label: '電話番号とメールで続ける',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const InputScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text(
                    '新規登録でお困りの方',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
