import 'package:flutter/material.dart';

class PushNotificationSettingsScreen extends StatefulWidget {
  final bool newMatch;
  final bool message;
  final bool messageLike;
  final bool treatLike;        // ご馳走Like
  final bool youMightLike;     // あなたが好みかも
  final bool promotions;       // オファーとプロモーション
  final bool inAppVibration;   // アプリ内バイブレーション
  final bool inAppSound;       // アプリ内音声

  const PushNotificationSettingsScreen({
    super.key,
    this.newMatch = true,
    this.message = true,
    this.messageLike = true,
    this.treatLike = true,
    this.youMightLike = true,
    this.promotions = false,
    this.inAppVibration = false,
    this.inAppSound = false,
  });

  @override
  State<PushNotificationSettingsScreen> createState() => _PushNotificationSettingsScreenState();
}

class _PushNotificationSettingsScreenState extends State<PushNotificationSettingsScreen> {
  late bool _newMatch;
  late bool _message;
  late bool _messageLike;
  late bool _treatLike;
  late bool _youMightLike;
  late bool _promotions;
  late bool _inAppVibration;
  late bool _inAppSound;

  @override
  void initState() {
    super.initState();
    _newMatch        = widget.newMatch;
    _message         = widget.message;
    _messageLike     = widget.messageLike;
    _treatLike       = widget.treatLike;
    _youMightLike    = widget.youMightLike;
    _promotions      = widget.promotions;
    _inAppVibration  = widget.inAppVibration;
    _inAppSound      = widget.inAppSound;
  }

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, color: Colors.white24);

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
              Navigator.pop(context, {
                'newMatch': _newMatch,
                'message': _message,
                'messageLike': _messageLike,
                'treatLike': _treatLike,
                'youMightLike': _youMightLike,
                'promotions': _promotions,
                'inAppVibration': _inAppVibration,
                'inAppSound': _inAppSound,
              });
            },
            child: const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        children: [
          _SwitchTile(
            title: '新しいマッチ',
            subtitle: '新しいマッチが見つかりました。',
            value: _newMatch,
            onChanged: (v) => setState(() => _newMatch = v),
          ),
          divider,
          _SwitchTile(
            title: 'メッセージ',
            subtitle: 'あなたに新しいメッセージが届いています。',
            value: _message,
            onChanged: (v) => setState(() => _message = v),
          ),
          divider,
          _SwitchTile(
            title: 'メッセージLike',
            subtitle: 'あなたにメッセージLikeした人がいます。',
            value: _messageLike,
            onChanged: (v) => setState(() => _messageLike = v),
          ),
          divider,
          _SwitchTile(
            title: 'ご馳走Like',
            subtitle: 'ご馳走Likeされました！',
            value: _treatLike,
            onChanged: (v) => setState(() => _treatLike = v),
          ),
          divider,
          _SwitchTile(
            title: 'あなたが好みかも',
            subtitle: '今日のあなたの好みが、セレクトされました！',
            value: _youMightLike,
            onChanged: (v) => setState(() => _youMightLike = v),
          ),
          divider,
          _SwitchTile(
            title: 'オファーとプロモーション',
            // 2行表示にしたいときは \n を入れる
            subtitle: '割引やオファー、プロモーションなどに関する\nsetteeの最新情報を受け取ります。',
            value: _promotions,
            onChanged: (v) => setState(() => _promotions = v),
          ),
          divider,
          _SwitchTile(
            title: 'アプリ内バイブレーション',
            value: _inAppVibration,
            onChanged: (v) => setState(() => _inAppVibration = v),
          ),
          divider,
          _SwitchTile(
            title: 'アプリ内音声',
            value: _inAppSound,
            onChanged: (v) => setState(() => _inAppSound = v),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    );

    final subtitleWidget = (subtitle == null)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle!,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
            ),
          );

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: (subtitle == null) ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleWidget, subtitleWidget],
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
