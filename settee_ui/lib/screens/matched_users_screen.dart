import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'user_profile_screen.dart';
import 'chat_screen.dart';

class MatchedUsersScreen extends StatefulWidget {
  final String userId;

  const MatchedUsersScreen({super.key, required this.userId});

  @override
  State<MatchedUsersScreen> createState() => _MatchedUsersScreenState();
}

class _MatchedUsersScreenState extends State<MatchedUsersScreen> {
  List<dynamic> matchedUsers = [];
  bool isLoading = true;
  // 対応拡張子（必要に応じて増減OK）
  static const List<String> kSupportedImageExts = ['jpg', 'jpeg', 'png', 'webp'];

  // 簡易キャッシュ（ユーザーごとの決定URLを保存）
  final Map<String, String?> _avatarUrlCache = {};

  // 画像更新後に手動でキャッシュ破棄したい場合に使う（任意）
  // 例: _cacheBuster['user123-1'] = DateTime.now().millisecondsSinceEpoch;
  final Map<String, int> _cacheBuster = {};

  Future<String?> _blockUser(String blockerId, String blockedId) async {
    final uri = Uri.parse('https://settee.jp/block/');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'blocker': blockerId, 'blocked': blockedId}),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body);
      return body['error']?.toString() ?? 'ブロックに失敗しました (${res.statusCode})';
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  Future<String?> _reportUser({
    required String targetId,
    String? reason, // 任意
  }) async {
    final uri = Uri.parse('https://settee.jp/report/');
    try {
      final payload = <String, dynamic>{
        'target': targetId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      };

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) return null; // OK
      // サーバ側のエラーメッセージを拾う
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        return body['detail']?.toString() ??
            body['error']?.toString() ??
            '通報に失敗しました (${res.statusCode})';
      } catch (_) {
        return '通報に失敗しました (${res.statusCode})';
      }
    } catch (e) {
      return '通信エラー: $e';
    }
  }

  void _showUserActions(BuildContext context, Map user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: const Text('ブロック', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx); // 一旦閉じる
                  final ok = await _confirmBlock(context, user['nickname']);
                  if (ok != true) return;

                  final err = await _blockUser(widget.userId, user['user_id']);
                  if (err == null) {
                    // 自分→相手の Like はサーバ側で即削除済み。UI からも除去
                    if (mounted) {
                      setState(() {
                        matchedUsers.removeWhere((u) => u['user_id'] == user['user_id']);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ブロックしました')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }
                },
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orangeAccent),
                title: const Text('通報する', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirmReport(context, user['nickname']);
                  if (ok != true) return;

                  final err = await _reportUser(targetId: user['user_id']);
                  if (err == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('通報しました')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmBlock(BuildContext context, String nickname) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'block',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return Opacity(
          opacity: curved.value,
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block, color: Colors.redAccent, size: 36),
                      const SizedBox(height: 12),
                      Text('ブロックしますか？', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        '$nickname さんをブロックします。あなたからのLikeは削除され、相手とのやり取りは制限されます。',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2D55)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('ブロックする', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        );
      },
    );
  }

  Future<bool?> _confirmReport(BuildContext context, String nickname) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'report',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return Opacity(
          opacity: curved.value,
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag_outlined, color: Color.fromARGB(255, 153, 87, 0), size: 36),
                      const SizedBox(height: 12),
                      Text('通報しますか？', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        '$nickname さんを運営に通報します。',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 153, 87, 0)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('通報する', style: TextStyle(color: Colors.white, fontSize: 14)),
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
        );
      },
    );
  }


  Future<String?> _getExistingImageUrl(String userId, int index, List<String> extensions) async {
    final busterKey = '$userId-$index';
    final buster = _cacheBuster[busterKey];

    for (final ext in extensions) {
      final url = 'https://settee.jp/images/$userId/${userId}_$index.$ext'
          '${buster != null ? '?t=$buster' : ''}';

      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          return url;
        }
      } catch (_) {
        // 通信エラー時は次の拡張子を試す
      }
    }
    return null;
  }

  Future<String?> _getAvatarUrl(String userId) async {
    // メモリキャッシュ
    if (_avatarUrlCache.containsKey(userId)) {
      return _avatarUrlCache[userId];
    }
    // index=1 をチェック
    final url = await _getExistingImageUrl(userId, 1, kSupportedImageExts);
    _avatarUrlCache[userId] = url;
    return url;
  }

  @override
  void initState() {
    super.initState();
    fetchMatchedUsers();
  }

  Future<void> fetchMatchedUsers() async {
    final url = Uri.parse('https://settee.jp/matched-users/${widget.userId}/');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        setState(() {
          matchedUsers = json.decode(response.body);
          isLoading = false;
        });
      } else {
        debugPrint('取得失敗: ${response.statusCode}');
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('通信エラー: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Image.asset('assets/white_logo_text.png', width: 90),
        centerTitle: true,
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.userId),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '検索',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'メッセージ',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : ListView.separated(
                    itemCount: matchedUsers.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.grey),
                    itemBuilder: (context, index) {
                      final user = matchedUsers[index] as Map<String, dynamic>;
                      final userId = user['user_id'] as String?;
                      final isDeleted = userId == '__deleted__';
                      final nickname = (user['nickname'] as String?) ??
                          (isDeleted ? '退会したユーザー' : '');

                      return ListTile(
                        key: ValueKey(userId ?? index),
                        // ===== 左側：アイコン =====
                        leading: isDeleted
                            ? const CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.person_off_rounded, color: Colors.white70),
                              )
                            : FutureBuilder<String?>(
                                future: _getAvatarUrl(userId!),
                                builder: (context, snapshot) {
                                  final imgUrl = snapshot.data;

                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const CircleAvatar(
                                      radius: 24,
                                      backgroundColor: Colors.white10,
                                      child: SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white70),
                                      ),
                                    );
                                  }

                                  if (imgUrl == null) {
                                    return const CircleAvatar(
                                      radius: 24,
                                      backgroundColor: Colors.white24,
                                      child: Icon(Icons.person, color: Colors.white70),
                                    );
                                  }

                                  return CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.white10,
                                    foregroundImage: NetworkImage(imgUrl),
                                    child: const Icon(Icons.person, color: Colors.white70),
                                  );
                                },
                              ),

                        // ===== 中央：名前 =====
                        title: Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),

                        // ===== 右側：メニュー（…） =====
                        // 退会ユーザーにはメニューを出さない
                        trailing: isDeleted
                            ? null
                            : PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                color: const Color(0xFF121212),
                                onSelected: (value) async {
                                  if (value == 'block') {
                                    final ok = await _confirmBlock(context, nickname);
                                    if (ok == true) {
                                      final err = await _blockUser(widget.userId, userId!);
                                      if (err == null) {
                                        if (context.mounted) {
                                          setState(() {
                                            // 自分の一覧から非表示にする
                                            matchedUsers.removeAt(index);
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('ブロックしました')),
                                          );
                                        }
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(err)),
                                          );
                                        }
                                      }
                                    }
                                  } else if (value == 'report') {
                                    final ok = await _confirmReport(context, nickname);
                                    if (ok == true) {
                                      final err = await _reportUser(targetId: user['user_id']);
                                      if (err == null) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('通報しました')),
                                          );
                                        }
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(err)),
                                          );
                                        }
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'block',
                                    child: Row(
                                      children: const [
                                        Icon(Icons.block, color: Colors.redAccent, size: 20),
                                        SizedBox(width: 10),
                                        Text('ブロック', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'report',
                                    child: Row(
                                      children: const [
                                        Icon(Icons.flag_outlined, color: Colors.orangeAccent, size: 20),
                                        SizedBox(width: 10),
                                        Text('通報する', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                        // ===== タップでチャットへ =====
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: userId ?? '__deleted__',
                                matchedUserNickname: nickname,
                              ),
                            ),
                          );
                        },

                        // 任意：ロングタップでもメニューを開けるように
                        onLongPress: isDeleted
                            ? null
                            : () {
                                // PopupMenu を開く簡易実装：trailingをタップしてね、でもOK
                                // 高度にやるなら GlobalKey でメニューを開く処理を追加
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context, String userId) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileBrowseScreen(currentUserId: userId)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.home_outlined, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DiscoveryScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.search, color: Colors.black),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),  // 文字を少し上に配置
            child: Image.asset(
              'assets/logo_text.png',
              width: 70,
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.mail, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.person_outline, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
