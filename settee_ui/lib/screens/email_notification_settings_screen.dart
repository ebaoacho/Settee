import 'package:flutter/material.dart';

class EmailNotificationSettingsScreen extends StatefulWidget {
  final String email;
  final bool emailVerified;
  final bool newMatch;
  final bool newMessage;
  final bool promotions;

  const EmailNotificationSettingsScreen({
    super.key,
    required this.email,
    this.emailVerified = false,
    this.newMatch = true,
    this.newMessage = true,
    this.promotions = true,
  });

  @override
  State<EmailNotificationSettingsScreen> createState() => _EmailNotificationSettingsScreenState();
}

class _EmailNotificationSettingsScreenState extends State<EmailNotificationSettingsScreen> {
  late bool _newMatch;
  late bool _newMessage;
  late bool _promotions;

  @override
  void initState() {
    super.initState();
    _newMatch = widget.newMatch;
    _newMessage = widget.newMessage;
    _promotions = widget.promotions;
  }

  @override
  Widget build(BuildContext context) {
    final divider = const Divider(height: 1, color: Colors.white24);

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
            onPressed: () {
              // 呼び出し元に現在の設定を返す
              Navigator.pop(context, {
                'newMatch': _newMatch,
                'newMessage': _newMessage,
                'promotions': _promotions,
              });
            },
            child: const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 見出し：メールアドレス
          const _SectionHeader('メールアドレス'),

          // メール表示（下線＋右に赤✓）
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.email,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                if (widget.emailVerified)
                  const Icon(Icons.check, color: Colors.redAccent, size: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Text(
              widget.emailVerified
                  ? 'あなたのメールアドレスが認証されました。'
                  : '未認証です',
              style: TextStyle(
                color: widget.emailVerified ? Colors.white60 : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),

          divider,

          // 確認メールを送信する
          InkWell(
            onTap: () {
              // TODO: 確認メール送信 API を叩く
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('確認メールを送信しました')),
              );
            },
            child: Container(
              color: Colors.black,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: const Text(
                '確認メールを送信する',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

          const _SectionSpacer(),

          // トグル群
          _SwitchCell(
            title: '新しいマッチ',
            value: _newMatch,
            onChanged: (v) => setState(() => _newMatch = v),
          ),
          divider,
          _SwitchCell(
            title: '新着メッセージ',
            value: _newMessage,
            onChanged: (v) => setState(() => _newMessage = v),
          ),
          divider,
          _SwitchCell(
            title: 'プロモーション\nsetteeからニュース、更新情報、キャンペーン情報を受信する',
            value: _promotions,
            onChanged: (v) => setState(() => _promotions = v),
            multiline: true,
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              '自分が購読したいメールを設定してください。全般、重要なものだけ、あるいは最低限のものの設定できます。メールの末尾にあるリンクから、いつでも購読解除できます。',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
            ),
          ),

          // すべて購読解除する
          const Divider(height: 1, color: Colors.white24),
          InkWell(
            onTap: () {
              setState(() {
                _newMatch = false;
                _newMessage = false;
                _promotions = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('すべて購読解除しました')),
              );
            },
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: const Text(
                'すべて購読解除する',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
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

class _SectionSpacer extends StatelessWidget {
  const _SectionSpacer();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 14);
}

class _SwitchCell extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool multiline;

  const _SwitchCell({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color.fromARGB(255, 48, 209, 88),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}
