// lib/cancellation_info_screen.dart
import 'package:flutter/material.dart';

class CancellationInfoScreen extends StatelessWidget {
  const CancellationInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // タブとページを同一配列で定義して数を常に一致させる
    final tabs = const <Tab>[
      Tab(text: 'iOS (Apple)'),
      // Tab(text: 'Android (Google)'),
    ];
    final pages = <Widget>[
      _GuideBody(children: const [
        _StepTitle('Appleのサブスクリプション管理画面から解約・変更します'),
        _StepText('1) iPhoneの「設定」アプリを開く'),
        _StepText('2) 画面上部の「Apple ID（ユーザ名）」をタップ'),
        _StepText('3)「サブスクリプション」をタップ'),
        _StepText('4)「Settee」を選択し、プラン変更または解約を選ぶ'),
        _NoteTitle('注意点'),
        _StepText('・アプリを削除しても自動的に解約されません'),
        _StepText('・解約手続き後も、更新日前日までは機能をご利用いただけます'),
        _FaqTitle('よくある質問'),
        _StepText('Q. 解約タイミングは？'),
        _StepText('A. 次回更新日の24時間以上前に行ってください'),
        _StepText('Q. 返金はできますか？'),
        _StepText('A. 課金はAppleによって処理されます。返金可否はAppleのポリシーに従います'),
      ]),
      // _GuideBody(children: const [
      //   _StepTitle('Google Playの定期購入管理から解約・変更します'),
      //   _StepText('1) Google Play ストアアプリを開く'),
      //   _StepText('2) 右上のプロフィールアイコン →「お支払いと定期購入」'),
      //   _StepText('3)「定期購入」から「Settee」を選択'),
      //   _StepText('4) プラン変更または解約を選ぶ'),
      //   _NoteTitle('注意点'),
      //   _StepText('・アプリを削除しても自動的に解約されません'),
      //   _StepText('・解約手続き後も、更新日前日までは機能をご利用いただけます'),
      //   _FaqTitle('よくある質問'),
      //   _StepText('Q. 解約タイミングは？'),
      //   _StepText('A. 次回更新日の24時間以上前に行ってください'),
      //   _StepText('Q. 返金はできますか？'),
      //   _StepText('A. 課金はGoogleによって処理されます。返金可否はGoogleのポリシーに従います'),
      // ]),
    ];

    // 念のため長さを強制一致（未来の編集で数がズレても落ちないように）
    final length = tabs.length.clamp(0, pages.length);

    return DefaultTabController(
      length: length,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('解約・更新の方法'),
          backgroundColor: Colors.black,
          bottom: TabBar(
            tabs: tabs.take(length).toList(),
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: pages.take(length).toList(),
        ),
      ),
    );
  }
}

class _GuideBody extends StatelessWidget {
  final List<Widget> children;
  const _GuideBody({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  final String text;
  const _StepTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _NoteTitle extends StatelessWidget {
  final String text;
  const _NoteTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.95),
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _FaqTitle extends StatelessWidget {
  final String text;
  const _FaqTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.95),
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  final String text;
  const _StepText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.90),
          fontSize: 13.5,
        ),
      ),
    );
  }
}
