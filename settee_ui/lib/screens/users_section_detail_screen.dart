import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// プロフィール詳細へ（読み取り専用の簡易画面）
class ReadOnlyUserDetailScreen extends StatelessWidget {
  final String targetUserId;
  const ReadOnlyUserDetailScreen({super.key, required this.targetUserId});

  Future<Map<String, dynamic>?> _fetchProfile() async {
    final r = await http.get(Uri.parse('https://settee.jp/get-profile/$targetUserId/'))
                        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('プロフィール詳細')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchProfile(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data!;
          // 基本情報・好み・求めているのは 等を素直に羅列
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p['nickname'] ?? ''}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),

                  // 見やすい日本語に整形
                  Text('マッチする人数: ${(p['match_multiple'] == true) ? 'みんなで' : 'ひとりで'}'),

                  // ▼ ここから追加：よく遊ぶエリア（丸いオブジェクト）
                  const SizedBox(height: 8),
                  const Text(
                    'よく遊ぶエリア',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (_) {
                      final List areasRaw = (p['selected_area'] as List?) ?? const [];
                      final List<String> areas = areasRaw
                          .map((e) => e?.toString().trim() ?? '')
                          .where((s) => s.isNotEmpty)
                          .toList();

                      if (areas.isEmpty) {
                        return const Text('未設定', style: TextStyle(color: Colors.white70));
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: areas.map((area) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999), // 丸カプセル
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.place, size: 14, color: Colors.black87),
                                const SizedBox(width: 6),
                                Text(
                                  area,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                  Text('性別: ${p['gender'] ?? '-'}'),
                  Text('MBTI: ${p['mbti'] ?? '-'}'),
                  Text('星座: ${p['zodiac'] ?? '-'}'),
                  Text('お酒: ${p['drinking'] ?? '-'}'),
                  Text('煙草: ${p['smoking'] ?? '-'}'),
                  const SizedBox(height: 12),
                  const Text('求めているのは', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${p['seeking'] ?? '-'}'),
                  const SizedBox(height: 12),
                  const Text('好み', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${p['preference'] ?? '-'}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class UsersSectionDetailScreen extends StatefulWidget {
  final String title;
  final String currentUserId;
  final List<dynamic> users; // [{user_id, nickname}, ... 10件想定]

  const UsersSectionDetailScreen({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.users,
  });

  @override
  State<UsersSectionDetailScreen> createState() => _UsersSectionDetailScreenState();
}

class _UsersSectionDetailScreenState extends State<UsersSectionDetailScreen> {
  int _msgLikeCredits = 0;
  int _superLikeCredits = 0;
  bool _setteePlusActive = false; // Treat(ごちそう)の可否に使用
  bool _loadingEnt = true;

  bool get _canMessageLike => _msgLikeCredits > 0;
  bool get _canSuperLike   => _superLikeCredits > 0;
  bool get _canTreatLike   => _setteePlusActive;

  String _likeLabel(int likeType) {
    switch (likeType) {
      case 1: return 'スーパーライク';
      case 2: return 'ごちそうライク';
      case 3: return 'メッセージライク';
      case 0:
      default: return '通常Like';
    }
  }

  Color _likeColor(int likeType) {
    switch (likeType) {
      case 1: return const Color(0xFF40C4FF); // 水色 Super
      case 2: return const Color(0xFFFFEB3B); // 黄色 Treat
      case 3: return const Color(0xFFFF9800); // オレンジ Message
      case 0:
      default: return const Color(0xFF9E9E9E); // グレー Normal
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchEntitlements();
  }

  int _toInt(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  bool _toBool(dynamic v, {bool def = false}) {
    if (v == null) return def;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return def;
  }

  Future<void> _fetchEntitlements() async {
    setState(() => _loadingEnt = true);
    try {
      final r = await http
          .get(Uri.parse('https://settee.jp/users/${widget.currentUserId}/entitlements/'))
          .timeout(const Duration(seconds: 10));

      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _msgLikeCredits   = _toInt(j['message_like_credits']);
          _superLikeCredits = _toInt(j['super_like_credits']);
          _setteePlusActive = _toBool(j['settee_plus_active']);
          _loadingEnt = false;
        });
      } else {
        setState(() => _loadingEnt = false);
        // エラー時の気づき用
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('entitlements取得失敗: ${r.statusCode}')),
        );
      }
    } catch (e) {
      setState(() => _loadingEnt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信エラー: $e')),
      );
    }
  }

  Future<void> _sendLike(String receiverId, int likeType) async {
    final label = _likeLabel(likeType);
    final color = _likeColor(likeType);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label を送信中…'),
        backgroundColor: color.withOpacity(0.85),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final r = await http.post(
        Uri.parse('https://settee.jp/like/'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'sender': widget.currentUserId,
          'receiver': receiverId,
          'like_type': likeType, // 0:通常, 1:Super, 2:ごちそう, 3:メッセージ
        }),
      ).timeout(const Duration(seconds: 10));

      final bodyText = r.body; // ← 詳細を見る

      if (r.statusCode == 200 || r.statusCode == 201) {
        await _fetchEntitlements(); // 残高反映
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label を送信しました')),
        );
        return;
      }

      // ここからエラーの扱い
      if (!mounted) return;

      // サーバの標準メッセージに寄せて分岐（日本語本文をそのまま表示）
      if (r.statusCode == 400 && bodyText.contains('既にLike済みです')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この相手には既にLike済みです')),
        );
      } else if (r.statusCode == 400 && bodyText.contains('指定されたユーザーが存在しません')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('送信先ユーザーが見つかりません')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました（${r.statusCode}）: $bodyText')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信エラー: $e')),
      );
    }
  }

  Widget _likeButtonsFor(String targetUserId) {
    final baseStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 通常Like（常に可）
        ElevatedButton.icon(
          style: baseStyle,
          onPressed: () => _sendLike(targetUserId, 0),
          icon: const Icon(Icons.thumb_up, size: 16),
          label: const Text('Like', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),

        // Super Like（クレジット必須）
        ElevatedButton.icon(
          style: baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              _canSuperLike ? null : Colors.grey.shade700,
            ),
          ),
          onPressed: _canSuperLike ? () => _sendLike(targetUserId, 1) : null,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('スーパー', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),

        // ごちそう Like（Settee+ 中のみ）
        ElevatedButton.icon(
          style: baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              _canTreatLike ? null : Colors.grey.shade700,
            ),
          ),
          onPressed: _canTreatLike ? () => _sendLike(targetUserId, 2) : null,
          icon: const Icon(Icons.fastfood, size: 16),
          label: const Text('ごちそう', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),

        // メッセージ Like（クレジット必須）
        ElevatedButton.icon(
          style: baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              _canMessageLike ? null : Colors.grey.shade700,
            ),
          ),
          onPressed: _canMessageLike ? () => _sendLike(targetUserId, 3) : null,
          icon: const Icon(Icons.message, size: 16),
          label: const Text('メッセージ', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<String?> _firstImageUrl(String userId) async {
    // 既存の Discovery と同じロジック
    const exts = ['jpg', 'jpeg', 'png'];
    for (final ext in exts) {
      final url = 'https://settee.jp/images/$userId/${userId}_1.$ext';
      try {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) return url;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.users; // 10件想定

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _loadingEnt
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final u = users[i];
                final uid = u['user_id'] as String;
                final nickname = (u['nickname'] ?? '') as String;

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 6)),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 上段：画像＋名前＋詳細へ
                      Row(
                        children: [
                          FutureBuilder<String?>(
                            future: _firstImageUrl(uid),
                            builder: (context, snap) {
                              final imageUrl = snap.data;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 72, height: 96,
                                  child: imageUrl != null
                                      ? Image.network(imageUrl, fit: BoxFit.cover)
                                      : Container(
                                          color: Colors.white12,
                                          child: const Icon(Icons.image_not_supported, color: Colors.white38),
                                        ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nickname,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ReadOnlyUserDetailScreen(targetUserId: uid),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.info_outline, size: 16),
                                    label: const Text('詳細を見る'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 下段：Like ボタン群（権限に応じて disable）
                      _likeButtonsFor(uid),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
