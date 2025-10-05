import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PhoneNumberEditScreen extends StatefulWidget {
  final String userId;          // ★ 追加：エンドポイント用
  final String initialPhone;    // 例: '+819012345678' / '09012345678'
  final bool isVerified;        // 表示用（任意）

  const PhoneNumberEditScreen({
    super.key,
    required this.userId,
    required this.initialPhone,
    this.isVerified = false,
  });

  @override
  State<PhoneNumberEditScreen> createState() => _PhoneNumberEditScreenState();
}

class _PhoneNumberEditScreenState extends State<PhoneNumberEditScreen> {
  late final TextEditingController _controller;
  late String _original;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _original = widget.initialPhone;
    _controller = TextEditingController(text: widget.initialPhone)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _showVerifiedCheck {
    final t = _controller.text.trim();
    // 表示上の✓は「元と同じ & もともと認証済み」のときだけ
    return widget.isVerified && t == _original && t.isNotEmpty && _isValidPhone(t);
  }

  // サーバ仕様に合わせた最小検証：先頭+は任意、数字のみ 8〜15桁
  bool _isValidPhone(String v) {
    final re = RegExp(r'^\+?\d{8,15}$');
    return re.hasMatch(v.trim());
  }

  Map<String, dynamic> _safeJson(String body) {
    try {
      final obj = jsonDecode(body);
      return (obj is Map<String, dynamic>) ? obj : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _submitPhoneChange() async {
    final phone = _controller.text.trim();

    if (!_isValidPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('電話番号の形式が不正です（先頭+任意・数字のみ・8〜15桁）')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // 末尾スラッシュ必須（APPEND_SLASH=True 対策）
      final uri = Uri(
        scheme: 'https',
        host: 'settee.jp',
        pathSegments: ['users', widget.userId, 'phone', 'change', ''],
      );

      final resp = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(const Duration(seconds: 15));

      String uiMsg;
      if (resp.statusCode == 200) {
        final data = _safeJson(resp.body);
        uiMsg = (data['message'] as String?) ?? '電話番号を更新しました';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uiMsg)));

        // 呼び出し元が扱いやすいよう Map を返す
        Navigator.pop(context, {
          'phone': phone,
          'serverRaw': data,
        });
        return;
      } else if (resp.statusCode == 409) {
        uiMsg = 'この電話番号は既に使用されています';
      } else if (resp.statusCode == 404) {
        uiMsg = 'ユーザーが存在しません';
      } else if (resp.statusCode == 400) {
        final data = _safeJson(resp.body);
        uiMsg = (data['error'] as String?) ?? '電話番号の形式が不正です';
      } else {
        uiMsg = 'サーバーエラーが発生しました（${resp.statusCode}）';
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uiMsg)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信に失敗しました：$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final divider = const Divider(height: 1, color: Colors.white24);
    final changed = _controller.text.trim() != _original.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submitPhoneChange,
            child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('電話番号'),

          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              keyboardType: TextInputType.phone,
              // 日本の「090…」の入力も、「+81…」の国際表記も通るように、ここではフォーマッタは付けない
              decoration: InputDecoration(
                isDense: true,
                hintText: '例) +819012345678 または 09012345678',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                suffixIcon: _showVerifiedCheck
                    ? const Icon(Icons.check, color: Colors.redAccent, size: 20)
                    : null,
              ),
            ),
          ),

          // TODO: 電話番号認証機能の実装
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          //   child: Text(
          //     changed
          //         ? '未認証（変更後は再認証が必要）'
          //         : (widget.isVerified ? '認証済み電話番号' : '未認証'),
          //     style: TextStyle(
          //       color: changed ? Colors.redAccent : (widget.isVerified ? Colors.white60 : Colors.redAccent),
          //       fontSize: 12,
          //     ),
          //   ),
          // ),

          // divider,

          InkWell(
            onTap: _submitting
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('「完了」を押すとサーバーに反映します')),
                    );
                  },
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                _submitting ? '送信中…' : '電話番号を変更する',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          divider,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          height: 1.1,
        ),
      ),
    );
  }
}
