import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_method_screen.dart';
import 'details_screen.dart';

// 規約のバージョン（更新時はここを上げる）
const String kTermsVersion = '2025-09-01';
const String kPrivacyVersion = '2025-09-01';
const String kCommunityVersion = '2025-09-01';
const String kSafetyVersion = '2025-09-01';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool agreeTerms = false;
  bool agreePrivacy = false;
  bool agreeCommunity = false;
  bool agreeSafety = false;
  bool agreeAll = false;

  bool get _enabled => agreeTerms && agreePrivacy && agreeCommunity && agreeSafety;

  @override
  void initState() {
    super.initState();
    _loadPreviousConsent();
  }

  Future<void> _loadPreviousConsent() async {
    // すでに同意済み（同一バージョン）ならスキップしたい場合に使用
    final prefs = await SharedPreferences.getInstance();
    final ok = prefs.getString('consent_terms') == kTermsVersion &&
        prefs.getString('consent_privacy') == kPrivacyVersion &&
        prefs.getString('consent_community') == kCommunityVersion &&
        prefs.getString('consent_safety') == kSafetyVersion;
    if (ok && mounted) {
      // 既にすべて同意済みなら即 SignUp に進ませたい場合はコメントアウトを外す
      // Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpMethodScreen()));
    }
  }

  Future<void> _saveConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('consent_terms', kTermsVersion);
    await prefs.setString('consent_privacy', kPrivacyVersion);
    await prefs.setString('consent_community', kCommunityVersion);
    await prefs.setString('consent_safety', kSafetyVersion);
    await prefs.setString('consent_at', DateTime.now().toIso8601String());
  }

  void _toggleAll(bool value) {
    setState(() {
      agreeAll = value;
      agreeTerms = value;
      agreePrivacy = value;
      agreeCommunity = value;
      agreeSafety = value;
    });
  }

  Future<void> _openPolicy(PolicySection s) async {
    // DetailsScreen の該当セクションを最初から開いた状態で表示（下の②-任意の対応とセット）
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsScreen(initialSection: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labelColor = Colors.white;
    const subColor = Colors.white70;
    const trackOn = Color.fromARGB(255, 48, 209, 88);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('同意の確認'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          const Text(
            'アカウント作成にあたり、以下の規約への同意が必要です。各規約をタップして内容をご確認ください。',
            style: TextStyle(color: subColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),

          _ConsentTile(
            title: '利用規約',
            checked: agreeTerms,
            onChanged: (v) => setState(() => agreeTerms = v),
            onView: () => _openPolicy(PolicySection.terms),
          ),
          _DividerThin(),
          _ConsentTile(
            title: 'プライバシーポリシー',
            checked: agreePrivacy,
            onChanged: (v) => setState(() => agreePrivacy = v),
            onView: () => _openPolicy(PolicySection.privacy),
          ),
          _DividerThin(),
          _ConsentTile(
            title: 'コミュニティガイドライン',
            checked: agreeCommunity,
            onChanged: (v) => setState(() => agreeCommunity = v),
            onView: () => _openPolicy(PolicySection.community),
          ),
          _DividerThin(),
          _ConsentTile(
            title: '安心・安全のガイドライン',
            checked: agreeSafety,
            onChanged: (v) => setState(() => agreeSafety = v),
            onView: () => _openPolicy(PolicySection.safety),
          ),

          const SizedBox(height: 10),
          _DividerThin(),
          // すべてに同意
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('すべてに同意', style: TextStyle(color: labelColor, fontWeight: FontWeight.w700)),
            value: agreeAll,
            onChanged: (v) => _toggleAll(v),
            activeColor: Colors.white,
            activeTrackColor: trackOn,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
          ),

          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _enabled
                ? () async {
                    await _saveConsent();
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpMethodScreen()),
                    );
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _enabled ? Colors.white : Colors.white24,
              foregroundColor: _enabled ? Colors.black : Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('同意して続ける', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),

          const SizedBox(height: 10),
          const Text(
            '同意はいつでも「設定」>「規約とガイドライン」から確認できます。',
            style: TextStyle(color: subColor, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onView;

  const _ConsentTile({
    required this.title,
    required this.checked,
    required this.onChanged,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onView,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
          // 「見る」
          TextButton(
            onPressed: onView,
            child: const Text('見る', style: TextStyle(color: Colors.white70)),
          ),
          // チェック
          Switch(
            value: checked,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Color.fromARGB(255, 48, 209, 88),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}

class _DividerThin extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(height: 1, color: Colors.white24);
}
