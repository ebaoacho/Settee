import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nickname_input_screen.dart';

class BirthDateInputScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String gender;

  const BirthDateInputScreen({
    super.key,
    required this.phone,
    required this.email,
    required this.gender,
  });

  @override
  State<BirthDateInputScreen> createState() => _BirthDateInputScreenState();
}

class _BirthDateInputScreenState extends State<BirthDateInputScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _navigated = false;
  String rawText = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        rawText = _controller.text;
      });

      if (!_navigated && _isValidDate(rawText)) {
        _navigateToNext();
      }
    });
  }

  bool _isValidDate(String raw) {
    if (raw.length != 8) return false;
    final dateStr = '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}';
    final parsedDate = DateTime.tryParse(dateStr);
    final now = DateTime.now();
    return parsedDate != null && parsedDate.isBefore(now);
  }

  void _navigateToNext() {
    if (_navigated) return;
    _navigated = true;
    Future.microtask(() {
      if (!mounted) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => NicknameInputScreen(
            phone: widget.phone,
            email: widget.email,
            gender: widget.gender,
            birthDate: rawText,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  List<InlineSpan> buildDynamicPlaceholder(String raw) {
    const template = ['Y', 'Y', 'Y', 'Y', '/', 'M', 'M', '/', 'D', 'D'];
    List<InlineSpan> spans = [];
    int rawIndex = 0;

    for (int i = 0; i < template.length; i++) {
      if (template[i] == '/') {
        spans.add(const TextSpan(
          text: ' / ',
          style: TextStyle(color: Colors.white70, fontSize: 24, letterSpacing: 2),
        ));
      } else {
        if (rawIndex < raw.length) {
          spans.add(TextSpan(
            text: raw[rawIndex],
            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 2),
          ));
        } else {
          spans.add(TextSpan(
            text: template[i],
            style: const TextStyle(color: Colors.white24, fontSize: 24, letterSpacing: 2),
          ));
        }
        rawIndex++;
      }
    }
    return spans;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 16.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
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
                        color: index <= 1 ? Colors.green : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 60),
            const Icon(Icons.cake, color: Colors.white70, size: 40),
            const SizedBox(height: 20),
            const Text(
              'あなたの生年月日は？',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '登録した生年月日は変更できません',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: 280,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    child: RichText(
                      text: TextSpan(
                        children: buildDynamicPlaceholder(rawText),
                      ),
                    ),
                  ),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    style: const TextStyle(
                      color: Colors.transparent,
                      fontSize: 24,
                      letterSpacing: 4,
                    ),
                    showCursor: false,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // ✅ 手動の「次へ」ボタン
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    if (_isValidDate(rawText)) {
                      _navigateToNext();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('正しい8桁の生年月日を入力してください')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('次へ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
