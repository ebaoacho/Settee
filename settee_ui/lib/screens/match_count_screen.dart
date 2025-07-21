import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'finish_setting_screen.dart';

class MatchCountScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String gender;
  final String birthDate;
  final String nickname;
  final String userId;
  final String password;
  final File? selectedImage;
  final List<String> selectedAreas;

  const MatchCountScreen({
    super.key,
    required this.phone,
    required this.email,
    required this.gender,
    required this.birthDate,
    required this.nickname,
    required this.userId,
    required this.password,
    required this.selectedImage,
    required this.selectedAreas,
  });

  @override
  State<MatchCountScreen> createState() => _MatchCountScreenState();
}

class _MatchCountScreenState extends State<MatchCountScreen> {
  String? selectedOption;
  bool isLoading = false;

  Future<void> _uploadImage(File imageFile, String userId) async {
    final url = Uri.parse('http://10.0.2.2:8000/upload-image/');
    final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';

    final request = http.MultipartRequest('POST', url)
      ..fields['user_id'] = userId
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType('image', mimeType.split('/').last),
          filename: p.basename(imageFile.path),
        ),
      );

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('画像アップロード失敗 (code: ${response.statusCode})');
    }
  }

  Future<void> _submitRegistration() async {
    if (selectedOption == null) return;
    setState(() => isLoading = true);

    try {
      final url = Uri.parse('http://10.0.2.2:8000/register/');
      final payload = {
        "phone": widget.phone,
        "email": widget.email,
        "gender": widget.gender,
        "birth_date": widget.birthDate,
        "nickname": widget.nickname,
        "user_id": widget.userId,
        "password": widget.password,
        "selected_area": widget.selectedAreas,
        "match_count": selectedOption!,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode != 201) {
        throw Exception('登録失敗 (code: ${response.statusCode})');
      }

      // 登録成功後に画像をアップロード
      if (widget.selectedImage != null) {
        await _uploadImage(widget.selectedImage!, widget.userId);
      }

      if (!mounted) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => FinalSettingScreen(userId: widget.userId),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通信エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Widget _buildOption({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final isSelected = (selectedOption == value);

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedOption = value;
        });
      },
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white38,
                width: 2,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 50,
              color: isSelected ? Colors.white : Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
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
                        color: index <= 7 ? Colors.green : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 60),
            const Text(
              'マッチする人数を選びましょう',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '後から変更することも可能です',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOption(label: 'ひとりでマッチ', icon: Icons.person, value: 'single'),
                _buildOption(label: 'みんなでマッチ', icon: Icons.group, value: 'group'),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (selectedOption != null && !isLoading)
                      ? _submitRegistration
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (selectedOption != null && !isLoading)
                        ? Colors.green
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('次へ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
