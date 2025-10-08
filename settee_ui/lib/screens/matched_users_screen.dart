import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'user_profile_screen.dart';
import 'chat_screen.dart';

enum _ItemKind { dm, group }

class _ChatListItem {
  final _ItemKind kind;
  final int? conversationId;
  final String? partnerUserId;
  final String title;
  final List<String> avatarUserIds;
  _ChatListItem.dm({required this.partnerUserId, required this.title, required this.avatarUserIds})
      : kind = _ItemKind.dm, conversationId = null;
  _ChatListItem.group({required this.conversationId, required this.title, required this.avatarUserIds})
      : kind = _ItemKind.group, partnerUserId = null;
}
// 画面クラスの先頭付近に追加
enum _ConvMode { single, double }

class _ConvInfo {
  final _ConvMode mode;
  final int? conversationId;
  const _ConvInfo(this.mode, this.conversationId);
}

class MatchedUsersScreen extends StatefulWidget {
  final String userId;

  const MatchedUsersScreen({super.key, required this.userId});

  @override
  State<MatchedUsersScreen> createState() => _MatchedUsersScreenState();
}

class _MatchedUsersScreenState extends State<MatchedUsersScreen> {
  bool _loading = true;
  List<_ChatListItem> _items = [];
  final Map<String, String> _nameById = {};

  // 対応拡張子（必要に応じて増減OK）
  static const List<String> kSupportedImageExts = ['jpg', 'jpeg', 'png', 'webp'];

  // 簡易キャッシュ（ユーザーごとの決定URLを保存）
  final Map<String, String?> _avatarUrlCache = {};

  // 画像更新後に手動でキャッシュ破棄したい場合に使う（任意）
  // 例: _cacheBuster['user123-1'] = DateTime.now().millisecondsSinceEpoch;
  final Map<String, int> _cacheBuster = {};

  final Map<String, _ConvInfo> _convCache = {}; // key = otherUserId

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future.wait([
      _fetchNameDictionary(),        // DM表示用に相手名の辞書を作る
      _buildItemsFromConversations() // 一覧の本体（DM/グループを会話単位で作る）
    ]);
    if (mounted) setState(() => _loading = false);
  }

  // 既存API: /matched-users/<me>/ は「名前辞書」としてだけ利用
  Future<void> _fetchNameDictionary() async {
    try {
      final uri = Uri.parse('https://settee.jp/matched-users/${widget.userId}/');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        for (final e in list) {
          final id = (e['user_id'] ?? '').toString();
          final nick = (e['nickname'] ?? '').toString();
          if (id.isNotEmpty && nick.isNotEmpty) _nameById[id] = nick;
        }
      }
    } catch (_) {}
  }

  // 一覧の本体: /conversations/user/<me>/ の結果から DM/グループを構築
  Future<void> _buildItemsFromConversations() async {
    final items = <_ChatListItem>[];
    try {
      final uri = Uri.parse('https://settee.jp/conversations/user/${widget.userId}/');
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        _items = items;
        return;
      }
      final List<dynamic> raw = jsonDecode(utf8.decode(res.bodyBytes));
      for (final it in raw) {
        final kind = (it['kind'] ?? '').toString().toLowerCase();
        final members = _extractMemberUserIds(it['members']);
        if (!members.contains(widget.userId)) continue; // 念のため

        if (kind == 'dm') {
          final other = members.firstWhere((m) => m != widget.userId, orElse: () => '');
          if (other.isEmpty) continue;
          final title = _nameById[other] ?? other;
          items.add(_ChatListItem.dm(
            partnerUserId: other,
            title: title,
            avatarUserIds: [other],
          ));
        } else if (kind == 'double') {
          final cid = (it['id'] is int) ? it['id'] as int : int.tryParse('${it['id']}');
          if (cid == null) continue;
          final preview = members.where((m) => m != widget.userId).take(3).toList();
          final title = 'グループ (${members.length})';
          items.add(_ChatListItem.group(
            conversationId: cid,
            title: title,
            avatarUserIds: preview,
          ));
        }
      }
    } catch (_) {}
    _items = items;
  }

  // グループは最大3人の縮小アバターを重ねて表示（DMは1枚）
  Widget _buildLeadingAvatars(_ChatListItem it) {
    final ids = it.avatarUserIds;
    if (ids.isEmpty) {
      return const CircleAvatar(radius: 24, backgroundColor: Colors.white24,
        child: Icon(Icons.people, color: Colors.white70));
    }
    if (ids.length == 1) {
      return FutureBuilder<String?>(
        future: _getAvatarUrl(ids.first),
        builder: (_, snap) {
          final u = snap.data;
          return CircleAvatar(
            radius: 24,
            backgroundImage: (u != null) ? NetworkImage(u) : null,
            backgroundColor: Colors.white10,
            child: (u == null) ? const Icon(Icons.person, color: Colors.white70) : null,
          );
        },
      );
    }
    return SizedBox(
      width: 52, height: 48,
      child: Stack(
        children: List.generate(ids.length.clamp(0, 3), (i) {
          return Positioned(
            left: i * 16.0, top: 2,
            child: FutureBuilder<String?>(
              future: _getAvatarUrl(ids[i]),
              builder: (_, snap) {
                final u = snap.data;
                return CircleAvatar(
                  radius: 18,
                  backgroundImage: (u != null) ? NetworkImage(u) : null,
                  backgroundColor: Colors.white10,
                  child: (u == null) ? const Icon(Icons.person, size: 18, color: Colors.white70) : null,
                );
              },
            ),
          );
        }),
      ),
    );
  }

  List<String> _extractMemberUserIds(dynamic raw) {
    final out = <String>{}; // 重複排除
    if (raw is! List) return out.toList();

    for (final e in raw) {
      if (e is String) {
        // すでに user_id の配列
        if (e.isNotEmpty) out.add(e);
        continue;
      }
      if (e is Map) {
        // ① { user_id: "demo_user_1", ... }
        final uid1 = (e['user_id'] ?? e['uid'] ?? '').toString();
        if (uid1.isNotEmpty) { out.add(uid1); continue; }

        // ② { user: "demo_user_1", ... }
        final u = e['user'];
        if (u is String && u.isNotEmpty) { out.add(u); continue; }

        // ③ { user: { user_id: "demo_user_1", ... }, ... }
        if (u is Map) {
          final uid2 = (u['user_id'] ?? u['uid'] ?? u['username'] ?? '').toString();
          if (uid2.isNotEmpty) { out.add(uid2); continue; }
        }

        // ④ どうしても user_id が見当たらない場合、e['id'] は DB の数値PKのことが多いので不採用
        //    → ここで無理に id を user_id として扱わない（判定が壊れるため）
      } else {
        final s = e?.toString();
        if (s != null && s.isNotEmpty) out.add(s);
      }
    }
    return out.toList();
  }

  Future<Set<int>> _fetchDoubleConvIdsFor(String uid) async {
    final uri = Uri.parse('https://settee.jp/conversations/user/$uid/');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return {};
      final List items = jsonDecode(utf8.decode(res.bodyBytes));
      final ids = <int>{};
      for (final it in items) {
        final kind = (it['kind'] ?? '').toString().toLowerCase();
        if (kind != 'double') continue;
        final cid = (it['id'] is int)
            ? it['id'] as int
            : int.tryParse('${it['id']}');
        if (cid != null) ids.add(cid);
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  Future<int?> _guessDoubleConversationWith(String otherUserId) async {
    // まずは ID 集合の共通部分で判定（members を見ない）
    final mine = await _fetchDoubleConvIdsFor(widget.userId);
    if (mine.isEmpty) return null;

    // 相手側の会話一覧が取れるなら共通集合で即決
    try {
      final theirs = await _fetchDoubleConvIdsFor(otherUserId);
      final shared = mine.intersection(theirs);
      if (shared.isNotEmpty) return shared.first;
    } catch (_) {
      // 続行（環境によっては他人の一覧が取れない想定）
    }

    // 相手一覧が取れない環境：自分の double 候補のメッセージを見て相手が喋っていれば該当とみなす
    for (final cid in mine) {
      try {
        final uri = Uri.parse('https://settee.jp/conversations/$cid/messages/');
        final res = await http.get(uri).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;
        final List msgs = jsonDecode(utf8.decode(res.bodyBytes));
        final talked = msgs.any((m) => (m is Map) && (m['sender']?.toString() == otherUserId));
        if (talked) return cid;
      } catch (_) {/* 次へ */}
    }
    return null;
  }

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

  Future<void> _prefetchConversationsForMe() async {
    final uri = Uri.parse('https://settee.jp/conversations/user/${widget.userId}/');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;

      final List<dynamic> items = jsonDecode(utf8.decode(res.bodyBytes));
      for (final it in items) {
        final kind = (it['kind'] ?? '').toString().toLowerCase();
        if (kind != 'double') continue;

        final int? cid = (it['id'] is int) ? it['id'] as int : int.tryParse('${it['id']}');
        if (cid == null) continue;

        // ← ここだけ置き換え
        final memberIds = _extractMemberUserIds(it['members']);
        if (!memberIds.contains(widget.userId)) continue;
        for (final m in memberIds) {
          if (m == widget.userId) continue;
          _convCache[m] = _ConvInfo(_ConvMode.double, cid);
        }
      }
    } catch (_) {/* ignore */}
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

   // 相手との会話モードを決定
  Future<_ConvInfo> _resolveModeForPair(String otherUserId) async {
    // 0) キャッシュ
    final cached = _convCache[otherUserId];
    if (cached != null) return cached;

    // 1) いつもどおり /conversations/user/me を見て members で判定
    try {
      final uri = Uri.parse('https://settee.jp/conversations/user/${widget.userId}/');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> items = jsonDecode(utf8.decode(res.bodyBytes));
        for (final it in items) {
          final kind = (it['kind'] ?? '').toString().toLowerCase();
          if (kind != 'double') continue;
          final int? cid = (it['id'] is int) ? it['id'] as int : int.tryParse('${it['id']}');
          if (cid == null) continue;

          final memberIds = _extractMemberUserIds(it['members']);
          if (memberIds.contains(widget.userId) && memberIds.contains(otherUserId)) {
            final info = _ConvInfo(_ConvMode.double, cid);
            _convCache[otherUserId] = info;
            return info;
          }
        }
      }
    } catch (_) {}

    // 2) members で掴めなかった → 共通の double 会話ID から特定
    final guessed = await _guessDoubleConversationWith(otherUserId);
    if (guessed != null) {
      final info = _ConvInfo(_ConvMode.double, guessed);
      _convCache[otherUserId] = info;
      return info;
    }

    // 3) それでも見つからなければシングル
    final info = const _ConvInfo(_ConvMode.single, null);
    _convCache[otherUserId] = info;
    return info;
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
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      final isGroup = it.kind == _ItemKind.group;
                      final title = it.title;
                      return ListTile(
                        leading: _buildLeadingAvatars(it),
                        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        trailing: isGroup
                            ? null
                            : PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                color: const Color(0xFF121212),
                                onSelected: (value) async {
                                  if (value == 'block') {
                                    final nick = title;
                                    final ok = await _confirmBlock(context, nick);
                                    if (ok == true) {
                                      final err = await _blockUser(widget.userId, it.partnerUserId!);
                                      if (err == null && context.mounted) {
                                        setState(() => _items.removeAt(index));
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブロックしました')));
                                      } else if (context.mounted && err != null) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                                      }
                                    }
                                  } else if (value == 'report') {
                                    final ok = await _confirmReport(context, title);
                                    if (ok == true) {
                                      final err = await _reportUser(targetId: it.partnerUserId!);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(err == null ? '通報しました' : err)),
                                        );
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'block', child: Row(children: [
                                    Icon(Icons.block, color: Colors.redAccent, size: 20), SizedBox(width: 10),
                                    Text('ブロック', style: TextStyle(color: Colors.white)),
                                  ])),
                                  PopupMenuItem(value: 'report', child: Row(children: [
                                    Icon(Icons.flag_outlined, color: Colors.orangeAccent, size: 20), SizedBox(width: 10),
                                    Text('通報する', style: TextStyle(color: Colors.white)),
                                  ])),
                                ],
                              ),
                        onTap: () {
                          if (isGroup) {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: '__group__',
                                matchedUserNickname: title,
                                headerMode: MatchMode.double,
                                conversationId: it.conversationId, // ★グループは会話IDで開く
                              ),
                            ));
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: it.partnerUserId!,
                                matchedUserNickname: title,
                                headerMode: MatchMode.single,
                              ),
                            ));
                          }
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
