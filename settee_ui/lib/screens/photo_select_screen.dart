import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'station_select_screen.dart';

class PhotoSelectScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String gender;
  final String birthDate;
  final String nickname;
  final String userId;
  final String password;

  const PhotoSelectScreen({
    super.key,
    required this.phone,
    required this.email,
    required this.gender,
    required this.birthDate,
    required this.nickname,
    required this.userId,
    required this.password,
  });

  @override
  State<PhotoSelectScreen> createState() => _PhotoSelectScreenState();
}

class _PhotoSelectScreenState extends State<PhotoSelectScreen> {
  File? _selectedImage;
  bool _isLoading = false;

  /// ここで「ピッカーがすでに起動中か？」を示すフラグを追加
  bool _isPicking = false;

  Future<void> _pickImage() async {
    // すでにピッカー起動中なら何もしない
    if (_isPicking) return;

    // これ以降は画像ピッカーが起動中とみなす
    _isPicking = true;

    // 権限リクエスト
    final status = await Permission.photos.request();

    if (status.isGranted) {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
        );

        if (picked != null && mounted) {
          setState(() {
            _selectedImage = File(picked.path);
          });
        }
      } catch (e) {
        // 何らかのエラーが起きた場合もフラグを戻す
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("画像の選択中にエラーが発生しました")),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("写真アクセスを許可してください")),
        );
      }
    }

    // ピッカー処理が終わったのでフラグ解除
    _isPicking = false;
  }

  void _clearImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _onNextPressed() async {
    if (_isLoading || _selectedImage == null) return;

    setState(() => _isLoading = true);

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => StationSelectScreen(
            phone: widget.phone,
            email: widget.email,
            gender: widget.gender,
            birthDate: widget.birthDate,
            nickname: widget.nickname,
            userId: widget.userId,
            password: widget.password,
            selectedImage: _selectedImage,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("エラーが発生しました")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ──────────── 上部ナビゲーションなど ────────────
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
                        color: index <= 5 ? Colors.green : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              'メイン写真を選ぶ',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'メインとなる写真を選択しましょう\n（後から変更することも可能です）',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // ──────────── 画像選択エリア ────────────
            GestureDetector(
              // すでに画像を選択済ならタップ禁止、それ以外は _pickImage を呼び出す
              onTap: _selectedImage == null ? _pickImage : null,
              child: _selectedImage == null
                  ? const DottedUploadBox()
                  : Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            _selectedImage!,
                            width: 220,
                            height: 300,
                            fit: BoxFit.cover,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _clearImage,
                        )
                      ],
                    ),
            ),
            const Spacer(),
            // ──────────── 次へボタン ────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_selectedImage != null && !_isLoading)
                      ? _onNextPressed
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        (_selectedImage != null && !_isLoading)
                            ? Colors.green
                            : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("次へ"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DottedUploadBox extends StatelessWidget {
  const DottedUploadBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white30, style: BorderStyle.solid, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_circle, color: Colors.greenAccent, size: 40),
            SizedBox(height: 10),
            Text("写真をアップロード", style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
