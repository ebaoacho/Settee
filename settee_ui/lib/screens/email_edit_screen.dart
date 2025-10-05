import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmailEditScreen extends StatefulWidget {
  final String userId;           // エンドポイント用
  final String initialEmail;
  final bool isVerified;         // 表示用（暫定運用なら false 推奨）

  const EmailEditScreen({
    super.key,
    required this.userId,
    required this.initialEmail,
    this.isVerified = false,
  });

  @override
  State<EmailEditScreen> createState() => _EmailEditScreenState();
}

class _EmailEditScreenState extends State<EmailEditScreen> {
  late final TextEditingController _controller;
  late String _original;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _original = widget.initialEmail;
    _controller = TextEditingController(text: widget.initialEmail)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _showVerifiedCheck {
    final t = _controller.text.trim();
    return widget.isVerified && t == _original && t.isNotEmpty && _isValidEmail(t);
  }

  bool _isValidEmail(String v) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v);
  }

  Future<void> _submitEmailChange() async {
    final email = _controller.text.trim();

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正しいメールアドレスを入力してください')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uri = Uri.parse('https://settee.jp/users/${Uri.encodeComponent(widget.userId)}/email/change/');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final body = jsonEncode({'email': email});

      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      String uiMsg;
      if (resp.statusCode == 200) {
        final data = _safeJson(resp.body);
        uiMsg = (data['message'] as String?) ?? 'メールアドレスを更新しました';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uiMsg)));

        Navigator.pop(context, {
          'email': email,
          'isVerified': false,   // 暫定運用では未認証扱いを推奨
          'serverRaw': data,
        });
        return;
      } else if (resp.statusCode == 409) {
        uiMsg = 'このメールアドレスは既に使用されています';
      } else if (resp.statusCode == 404) {
        uiMsg = 'ユーザーが存在しません';
      } else if (resp.statusCode == 400) {
        final data = _safeJson(resp.body);
        uiMsg = (data['error'] as String?) ?? 'メールアドレスの形式が不正です';
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

  Map<String, dynamic> _safeJson(String body) {
    try {
      final obj = jsonDecode(body);
      return (obj is Map<String, dynamic>) ? obj : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
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
            onPressed: _submitting ? null : _submitEmailChange,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _EmailSectionHeader('メールアドレス'),

          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                isDense: true,
                hintText: 'メールアドレス',
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

          // TODO: メールアドレスの認証処理
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          //   child: Text(
          //     changed
          //         ? '未認証（変更後は再認証が必要）'
          //         : (widget.isVerified ? '認証済みメールアドレス' : '未認証'),
          //     style: TextStyle(
          //       color: changed
          //           ? Colors.redAccent
          //           : (widget.isVerified ? Colors.white60 : Colors.redAccent),
          //       fontSize: 12,
          //     ),
          //   ),
          // ),

          divider,

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
                _submitting ? '送信中…' : 'メールアドレスを変更する',
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

class _EmailSectionHeader extends StatelessWidget {
  final String text;
  const _EmailSectionHeader(this.text);

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
