import 'package:flutter/material.dart';
import 'phone_number_edit_screen.dart';
import 'email_edit_screen.dart';
import 'email_notification_settings_screen.dart';
import 'push_notification_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'details_screen.dart' show DetailsScreen, PolicySection;

import 'package:url_launcher/url_launcher.dart';


class SettingsScreen extends StatelessWidget {
  final String userId;
  final String phoneNumber;
  final String email;
  final String appVersion;

  const SettingsScreen({
    super.key,
    required this.userId,
    required this.phoneNumber,
    required this.email,
    this.appVersion = 'v1.0.0',
  });

  Future<bool> _confirmDeletion(BuildContext context) async {
    return await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'delete',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Opacity(
            opacity: curved.value,
            child: Center(
              child: Transform.scale(
                scale: 0.92 + 0.08 * curved.value, // 0.92→1.0
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(ctx).size.width * 0.86,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 26, offset: Offset(0, 14)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // アイコンバッジ（削除アイコン＋赤グラデ）
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF5E7E), Color(0xFFFF2D55)],
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x55FF2D55), blurRadius: 14),
                            ],
                          ),
                          child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'アカウントを削除しますか？',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'この操作は取り消せません。プロフィールや画像、いいね等が削除されます。\n\n'
                          '※メッセージ履歴は相手側の文脈保持のため残ります。',
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.white.withOpacity(0.28)),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('キャンセル'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF2D55),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  shadowColor: const Color(0x66FF2D55),
                                  elevation: 6,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('削除する'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ) ?? false;
  }

  Future<String?> _askPassword(BuildContext context) async {
    final controller = TextEditingController();
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'password',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        bool obscure = true;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Opacity(
            opacity: curved.value,
            child: Center(
              child: Transform.scale(
                scale: 0.92 + 0.08 * curved.value, // 0.92→1.0 のスケール演出
                child: Material(
                  color: Colors.transparent,
                  child: StatefulBuilder(
                    builder: (ctx, setState) {
                      final canSubmit = controller.text.trim().isNotEmpty;
                      return Container(
                        width: MediaQuery.of(ctx).size.width * 0.86,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212).withOpacity(0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 26, offset: Offset(0, 14)),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // アイコンバッジ（鍵アイコン＋赤グラデ）
                            Container(
                              width: 54, height: 54,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5E7E), Color(0xFFFF2D55)],
                                ),
                                boxShadow: const [BoxShadow(color: Color(0x55FF2D55), blurRadius: 14)],
                              ),
                              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              '本人確認のためパスワードを入力',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'アカウントを削除するのが本人であることを確認するために、'
                              '現在のパスワードの入力をお願いしています。',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: controller,
                              obscureText: obscure,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (v) {
                                final trimmed = v.trim();
                                if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: '現在のパスワード',
                                hintStyle: const TextStyle(color: Colors.white38),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.white.withOpacity(0.28)),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => Navigator.pop(ctx, null),
                                    child: const Text('キャンセル'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: canSubmit ? const Color(0xFFFF2D55) : const Color(0x44FFFFFF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      shadowColor: canSubmit ? const Color(0x66FF2D55) : Colors.transparent,
                                      elevation: canSubmit ? 6 : 0,
                                    ),
                                    onPressed: canSubmit
                                        ? () => Navigator.pop(ctx, controller.text.trim())
                                        : null,
                                    child: const Text('送信'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _deleteAccount({
    required String userId,
    required String password,
  }) async {
    final uri = Uri.parse('https://settee.jp/users/$userId/delete/');

    try {
      // DELETE で JSON を送りたい場合、サーバ側は request.data を読めるよう POST も許容済み。
      // ここは DELETE をまず試し、405等なら POST にフォールバック。
      final deleteResp = await http.Request('DELETE', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'password': password});
      final streamed = await deleteResp.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        return null; // success
      }

      // DELETE がうまくいかない環境用フォールバック：POST
      if (resp.statusCode == 405 || resp.statusCode == 400 || resp.statusCode == 404) {
        final postResp = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'password': password}),
        );
        if (postResp.statusCode == 200) return null;

        try {
          final body = jsonDecode(postResp.body);
          return body['error']?.toString() ?? '削除に失敗しました (${postResp.statusCode})';
        } catch (_) {
          return '削除に失敗しました (${postResp.statusCode})';
        }
      }

      try {
        final body = jsonDecode(resp.body);
        return body['error']?.toString() ?? '削除に失敗しました (${resp.statusCode})';
      } catch (_) {
        return '削除に失敗しました (${resp.statusCode})';
      }
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  // バージョン1のヘルプ＆サポート
  Future<void> _openHelpForm(BuildContext context) async {
    final uri = Uri.parse('https://forms.gle/xcW5hVsFWZ7idoaMA');
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication, // ← アプリ外部（ブラウザ）で開く
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブラウザを開けませんでした')),
      );
    }
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
            onPressed: () => Navigator.pop(context),
            child: const Text('完了', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('アカウント設定'),
          _SettingsCell(
            title: '電話番号',
            value: phoneNumber,
            onTap: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (_) => PhoneNumberEditScreen(
                    userId: userId,                // ★ 追加：必須
                    initialPhone: phoneNumber,
                    // isVerified: true,           // 表示用に必要なら
                  ),
                ),
              );

              if (result != null) {
                final newPhone = result['phone'] as String;
                // ここで状態更新や保存処理へ（SettingsScreen は Stateless なので親に委ねる or Provider等で反映）
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('電話番号を更新しました')),
                );
              }
            },
          ),
          divider,
          _SettingsCell(
            title: 'メールアドレス',
            value: email, // 現在のメール
            onTap: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (_) => EmailEditScreen(
                    userId: userId,
                    initialEmail: email,
                    isVerified: false,     // 暫定運用なら false 推奨
                  ),
                ),
              );

              if (result != null) {
                final newEmail = result['email'] as String;
                final isVerified = result['isVerified'] as bool; // 暫定では false
                // ローカル状態やプロバイダを更新
              }
            },
          ),


          const _SectionSpacer(),

          // const _SectionSpacer(),

          // TODO: 通知機能
          // const _SectionHeader('通知'),
          // _SettingsCell(
          //   title: 'メールアドレス',
          //   onTap: () async {
          //     final result = await Navigator.push<Map<String, bool>>(
          //       context,
          //       MaterialPageRoute(
          //         builder: (_) => EmailNotificationSettingsScreen(
          //           email: email,             // SettingsScreen の引数や状態から渡す
          //           emailVerified: false,      // 認証状態に合わせて
          //           newMatch: true,           // 既存値があればそれを
          //           newMessage: true,
          //           promotions: true,
          //         ),
          //       ),
          //     );

          //     if (result != null) {
          //       final newMatch = result['newMatch'] ?? true;
          //       final newMessage = result['newMessage'] ?? true;
          //       final promotions = result['promotions'] ?? true;

          //       ScaffoldMessenger.of(context).showSnackBar(
          //         const SnackBar(content: Text('通知設定を更新しました')),
          //       );
          //     }
          //   },
          // ),
          // divider,
          // _SettingsCell(
          //   title: 'プッシュ通知',
          //   onTap: () async {
          //     final result = await Navigator.push<Map<String, bool>>(
          //       context,
          //       MaterialPageRoute(
          //         builder: (_) => const PushNotificationSettingsScreen(
          //           newMatch: true,
          //           message: true,
          //           messageLike: true,
          //           treatLike: true,
          //           youMightLike: true,
          //           promotions: false,
          //           inAppVibration: false,
          //           inAppSound: false,
          //         ),
          //       ),
          //     );

          //     if (result != null) {
          //       ScaffoldMessenger.of(context).showSnackBar(
          //         const SnackBar(content: Text('プッシュ通知設定を更新しました')),
          //       );
          //     }
          //   },
          // ),

          // const _SectionSpacer(),

          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          //   child: Center(
          //     child: OutlinedButton(
          //       style: OutlinedButton.styleFrom(
          //         side: const BorderSide(color: Colors.white),
          //         foregroundColor: Colors.white,
          //         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          //       ),
          //       onPressed: () {
          //         // TODO: 購入復元処理
          //         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('購入を復元')));
          //       },
          //       child: const Text('購入を復元'),
          //     ),
          //   ),
          // ),

          const _SectionSpacer(),

          const _SectionHeader('お問い合わせ'),
            _SettingsCell(
              title: 'ヘルプ＆サポート',
              onTap: () => _openHelpForm(context),
            ),

          const _SectionSpacer(),

          const _SectionHeader('Setteeについて'),
          // TODO: 会社概要が必要か否かを要確認
          // _SettingsCell(
          //   title: '会社概要',
          //   onTap: () {},
          // ),
          // divider,
          _SettingsCell(
            title: '利用規約',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DetailsScreen(initialSection: PolicySection.terms),
                ),
              );
            },
          ),
          divider,
          _SettingsCell(
            title: 'プライバシーポリシー',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DetailsScreen(initialSection: PolicySection.privacy),
                ),
              );
            },
          ),
          divider,
          // TODO: クッキーポリシーが必要か否かを要確認
          // _SettingsCell(
          //   title: 'クッキーポリシー',
          //   onTap: () {},
          // ),
          // divider,
          _SettingsCell(
            title: 'コミュニティガイドライン',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DetailsScreen(initialSection: PolicySection.community),
                ),
              );
            },
          ),
          divider,
          _SettingsCell(
            title: '安心・安全のガイドライン',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DetailsScreen(initialSection: PolicySection.safety),
                ),
              );
            },
          ),

          const _SectionSpacer(),
          const _SectionHeader('アカウント'),
          _SettingsCell(
            title: 'ログアウト',
            isDestructive: true,
            onTap: () async {
              final ok = await showModernLogoutDialog(context) ?? false;
              if (!ok) return;

              // 端末ローカルの情報を“まるごと”削除
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
          ),
          _SettingsCell(
            title: 'アカウント削除',
            isDestructive: true,
            onTap: () async {
              final confirmed = await _confirmDeletion(context);
              if (!confirmed) return;

              final password = await _askPassword(context);
              if (password == null || password.isEmpty) return;

              // サーバ呼び出し
              final err = await _deleteAccount(
                userId: userId,      // SettingsScreen の引数でもらっている userId
                password: password,
              );

              if (err == null) {
                // 端末ローカルの情報を全削除
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('アカウントを削除しました')),
                );
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              } else {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err)),
                );
              }
            },
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'バージョン$appVersion',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
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
  Widget build(BuildContext context) {
    return const SizedBox(height: 14);
  }
}

class _SettingsCell extends StatelessWidget {
  final String title;
  final String? value;
  final bool isDestructive;
  final VoidCallback? onTap;

  const _SettingsCell({
    super.key,
    required this.title,
    this.value,
    this.isDestructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : Colors.white;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: color, fontSize: 16),
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  value!,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showModernLogoutDialog(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'logout',
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Opacity(
          opacity: curved.value,
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value, // 0.92→1.0 のスケール
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 26, offset: Offset(0, 14)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // アイコンバッジ
                      Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5E7E), Color(0xFFFF2D55)],
                          ),
                          boxShadow: const [BoxShadow(color: Color(0x55FF2D55), blurRadius: 14)],
                        ),
                        child: const Icon(Icons.logout_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'ログアウトしますか？',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'アプリからサインアウトします。再度利用するにはログインが必要です。',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withOpacity(0.28)),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF2D55),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                shadowColor: const Color(0x66FF2D55),
                                elevation: 6,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('ログアウト'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
