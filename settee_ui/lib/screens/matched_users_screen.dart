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

  _ChatListItem.dm({
    required this.partnerUserId,
    required this.title,
    required this.avatarUserIds,
  })  : kind = _ItemKind.dm,
        conversationId = null;

  _ChatListItem.group({
    required this.conversationId,
    required this.partnerUserId,
    required this.title,
    required this.avatarUserIds,
  })  : kind = _ItemKind.group;
}

// 画面クラスの先頭付近に追加
enum _ConvMode { single, double }

class _ConvInfo {
  final _ConvMode mode;
  final int? conversationId;
  const _ConvInfo(this.mode, this.conversationId);
}

class _Member {
  final String userId;
  final String? nickname;   // APIにあれば拾う
  final String role;        // 'owner' or 'member'
  final String? invitedBy;  // user_id（なければnull）
  _Member({required this.userId, this.nickname, required this.role, this.invitedBy});
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

  // null/非Map/非文字列も安全に文字へ
  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  String? _extractUserId(dynamic u) {
    if (u == null) return null;
    if (u is String && u.isNotEmpty) return u;
    if (u is Map) {
      final a = _asString(u['user_id']);
      if (a.isNotEmpty) return a;
      final b = _asString(u['uid']);
      if (b.isNotEmpty) return b;
      final c = _asString(u['username']);
      if (c.isNotEmpty) return c;
    }
    return null;
  }

  String _displayNameFor(String uid, Map<String,String> nameById) {
    return nameById[uid] ?? uid;
  }

  List<_Member> _parseMembersRich(dynamic raw) {
    final out = <_Member>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is Map) {
        final uid = _extractUserId(e['user']) ?? _asString(e['user_id']);
        if (uid.isEmpty) continue;
        final nick = _asString(e['nickname']).isNotEmpty ? _asString(e['nickname']) : null;
        final role = (_asString(e['role']).isNotEmpty) ? _asString(e['role']) : 'member';

        // invited_by は user_id か userオブジェクト想定の両対応
        String? invitedBy;
        final rawInv = e['invited_by'];
        if (rawInv != null) {
          invitedBy = _extractUserId(rawInv) ?? _asString(rawInv);
          if (invitedBy!.isEmpty) invitedBy = null;
        }

        out.add(_Member(userId: uid, nickname: nick, role: role, invitedBy: invitedBy));
      } else if (e is String && e.isNotEmpty) {
        out.add(_Member(userId: e, nickname: null, role: 'member', invitedBy: null));
      }
    }
    return out;
  }

  List<String> _extractMatchedPairUserIds(dynamic raw) {
    final ids = <String>[];
    if (raw == null) return ids;

    String? _take(dynamic v) {
      // user_id らしきものを吸い上げ
      if (v == null) return null;
      if (v is String && v.isNotEmpty) return v;
      if (v is Map) {
        final a = _asString(v['user_id']);
        if (a.isNotEmpty) return a;
        final b = _asString(v['uid']);
        if (b.isNotEmpty) return b;
        final c = _asString(v['username']);
        if (c.isNotEmpty) return c;
      }
      final s = _asString(v);
      return s.isNotEmpty ? s : null;
    }

    if (raw is List) {
      for (final e in raw) {
        final t = _take(e);
        if (t != null && t.isNotEmpty) ids.add(t);
      }
    } else if (raw is Map) {
      // 想定されるキーを総当たり
      for (final k in ['a','b','first','second','matched_pair_a','matched_pair_b','user_a','user_b']) {
        if (raw.containsKey(k)) {
          final t = _take(raw[k]);
          if (t != null && t.isNotEmpty) ids.add(t);
        }
      }
    } else {
      // "u1,u2" のような文字列も一応対応
      final s = _asString(raw);
      if (s.contains(',')) {
        ids.addAll(s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty));
      }
    }
    return ids.toSet().take(2).toList(); // 重複排除して2件まで
  }

  T? _firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
    for (final x in it) {
      if (test(x)) return x;
    }
    return null;
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

        if (kind == 'dm') {
          // ---- DM
          final membersRich = _parseMembersRich(it['members']);
          final me = widget.userId;
          String other = membersRich
              .map((m) => m.userId)
              .firstWhere((id) => id.isNotEmpty && id != me, orElse: () => '');

          if (other.isEmpty) {
            final pair = _extractMatchedPairUserIds(it['matched_pair']);
            other = pair.firstWhere((id) => id != me, orElse: () => '');
          }
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

          final membersRich = _parseMembersRich(it['members']);

          // ニックネーム辞書補完
          for (final m in membersRich) {
            if (m.nickname != null && m.nickname!.isNotEmpty) {
              _nameById.putIfAbsent(m.userId, () => m.nickname!);
            }
          }

          final me = widget.userId;

          // ① オーナー2名（matched_pair優先、なければrole=owner）
          List<String> owners = _extractMatchedPairUserIds(it['matched_pair']);
          if (owners.length < 2) {
            owners = membersRich.where((m) => m.role == 'owner').map((m) => m.userId).toList();
          }
          if (owners.length < 2) {
            // debugPrint('[List] double cid=$cid owners不足: $owners');
            continue;
          }
          final ownerA = owners[0];
          final ownerB = owners[1];

          final ownerAName = _displayNameFor(ownerA, _nameById);
          final ownerBName = _displayNameFor(ownerB, _nameById);

          // ② 自分の参加情報（自分がmemberならinvited_byに招待者）
          final meEntry = _firstWhereOrNull<_Member>(membersRich, (m) => m.userId == me)
              ?? _Member(userId: me, role: 'member', invitedBy: null);
          final inviterId = meEntry.invitedBy; // null -> 自分はオーナー
          final isOwner   = owners.contains(me);

          // ③ 相方オーナー（リーディング画像＆タイトルの“左の人”）
          String partnerOwnerId;
          if (isOwner) {
            // オーナー：もう一方のオーナー
            partnerOwnerId = (ownerA == me) ? ownerB : ownerA;
          } else {
            // 非オーナー：自分を招待したオーナーではない方
            final inv = inviterId ?? ownerA; // safety
            partnerOwnerId = (ownerA == inv) ? ownerB : ownerA;
          }
          final partnerOwnerName = _displayNameFor(partnerOwnerId, _nameById);

          // ④ その相方オーナーが招待した人
          final partnerSideFriend = _firstWhereOrNull<_Member>(
            membersRich,
            (m) => m.role != 'owner' && m.invitedBy == partnerOwnerId,
          );
          final partnerSideFriendName = (partnerSideFriend != null)
              ? _displayNameFor(partnerSideFriend.userId, _nameById)
              : '未招待の友だち';

          // ⑤ 自分が招待した人（オーナー時にサブタイトルで使う）
          final myInvitedFriend = _firstWhereOrNull<_Member>(
            membersRich,
            (m) => m.role != 'owner' && m.invitedBy == me,
          );
          final myInvitedFriendName = (myInvitedFriend != null)
              ? _displayNameFor(myInvitedFriend.userId, _nameById)
              : '未招待の友だち';

          // ⑥ サブタイトル右側の相手
          //    - オーナー: 自分が招待した人
          //    - 非オーナー: 自分を招待した人
          final subtitleRightName = isOwner
              ? myInvitedFriendName
              : _displayNameFor(inviterId ?? '', _nameById);

          // ⑦ タイトル/サブタイトル（“と”で連結）
          //    オーナー：     タイトル= マッチ相手(相方オーナー) と その人が招待した人
          //                   サブ      = あなた と 自分が招待した人
          //    非オーナー：   タイトル= 招待者ではない方のオーナー と その人が招待した人
          //                   サブ      = あなた と 自分を招待した人
          final titleLine1 = '$partnerOwnerName と $partnerSideFriendName';
          final titleLine2 = 'あなたと $subtitleRightName';

          // ⑧ リーディング画像は常に “相方オーナー” のみ
          final leadingIds = <String>[partnerOwnerId];

          // デバッグ
          // debugPrint('[List] double cid=$cid me=$me isOwner=$isOwner inviter=$inviterId '
          //     'owners=$owners partnerOwner=$partnerOwnerId partnerFriend=${partnerSideFriend?.userId ?? "-"} '
          //     'myFriend=${myInvitedFriend?.userId ?? "-"} title1="$titleLine1" title2="$titleLine2"');

          items.add(_ChatListItem.group(
            conversationId: cid,
            partnerUserId: partnerOwnerId,  // ← チャットに渡す“相方オーナー”
            title: '$titleLine1\n$titleLine2',
            avatarUserIds: leadingIds,      // ← 画像は相方オーナーのみ
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
                ? Center(
                    child: Image.asset(
                      'assets/loading_logo.gif',
                      width: 80,
                      height: 80,
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      final isGroup = it.kind == _ItemKind.group;
                      final lines   = it.title.split('\n');
                      final title1  = lines.first;
                      final title2  = (lines.length > 1) ? lines.sublist(1).join('\n') : null;
                      return ListTile(
                      leading: _buildLeadingAvatars(it),
                      title: Text(
                        title1,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      // ★ グループのみ2行目を出す（DMは1行のままでもOK）
                      subtitle: isGroup && title2 != null
                          ? Text(title2, style: const TextStyle(color: Colors.white70))
                          : null,
                        trailing: isGroup
                            ? null
                            : PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                color: const Color(0xFF121212),
                                onSelected: (value) async {
                                  if (value == 'block') {
                                    final nick = title1;
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
                                    final ok = await _confirmReport(context, title1);
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
                            final partnerId   = it.partnerUserId!;                 // 相手 userId
                            final partnerName = _nameById[partnerId] ?? partnerId; // 相手の単独名
                            final lines  = it.title.split('\n');
                            final title1 = lines.first; // "あみ と ゆき" のようなナビ用の見出し

                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: partnerId,
                                matchedUserNickname: title1,   // ← AppBar 用（"あみ と ゆき"）
                                partnerSoloName: partnerName,  // ← バナー文言用（"あみ"）
                                headerMode: MatchMode.double,
                                conversationId: it.conversationId,
                              ),
                            ));
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: it.partnerUserId!,
                                matchedUserNickname: title1,
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

  Route<T> _noAnimRoute<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
    maintainState: false, // 前画面を保持しない（→ タイマー等は dispose される）
    opaque: true,
  );

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
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(ProfileBrowseScreen(currentUserId: userId)),
                (route) => false,
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.home_outlined, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(DiscoveryScreen(userId: userId)),
                (route) => false,
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
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(UserProfileScreen(userId: userId)),
                (route) => false,
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