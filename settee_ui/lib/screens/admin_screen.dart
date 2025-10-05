// admin_screen.dart（抜粋・置き換え用）
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart'; // ログアウト遷移用

const _kBase = 'https://settee.jp';

// ---- 短命トークンの簡易管理（メモリ保持） ----
class _AdminAuth {
  String? token;
  DateTime? expiresAt;

  Future<bool> ensureTokenFromPrefs() async {
    if (token != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()))) return true;
    final prefs = await SharedPreferences.getInstance();
    final tok = prefs.getString('admin_access');
    final exp = prefs.getInt('admin_exp') ?? 0;
    if (tok != null && exp > DateTime.now().millisecondsSinceEpoch) {
      token = tok;
      expiresAt = DateTime.fromMillisecondsSinceEpoch(exp);
      return true;
    }
    return false;
  }

  Map<String, String> authHeaders() => {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
}

class AdminScreen extends StatefulWidget {
  final String currentUserId;
  const AdminScreen({super.key, required this.currentUserId});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with TickerProviderStateMixin {
  late final TabController _tab;
  final _auth = _AdminAuth();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _logoutAll() async {
    // 通常ログイン情報も消す
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    // 管理トークン破棄
    _auth.token = null;
    _auth.expiresAt = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settee管理者'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'ログアウト',
            onPressed: _logoutAll,
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.verified_user_outlined), text: '本人確認'),
            Tab(icon: Icon(Icons.photo_library_outlined), text: '写真'),
            Tab(icon: Icon(Icons.flag_outlined), text: '通報'),
            Tab(icon: Icon(Icons.gavel_outlined), text: 'BAN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _AdminKycTab(auth: _auth),
          _AdminPhotosByUserTab(auth: _auth),
          _AdminReportsTab(auth: _auth),
          _AdminBanTab(auth: _auth),
        ],
      ),
    );
  }
}

// ============ KYC（本人確認）タブ ============
class _AdminKycTab extends StatefulWidget {
  final _AdminAuth auth;
  const _AdminKycTab({required this.auth});

  @override
  State<_AdminKycTab> createState() => _AdminKycTabState();
}

class _AdminKycTabState extends State<_AdminKycTab> {
  // ====== 設定 ======
  static const String _host = 'https://settee.jp';
  static const int _pageSize = 50;

  // ====== 状態 ======
  final List<String> _userIds = [];
  bool _loadingIds = false;
  int _offset = 0;

  // 展開時に使う詳細キャッシュ（各ユーザの KYC 画像配列）
  final Map<String, List<Map<String, dynamic>>> _kycByUser = {};
  final Set<String> _loadingUsers = {};

  // サマリー（総枚数 / 未確認枚数）
  final Map<String, int> _totalCount = {};
  final Map<String, int> _unreviewedCount = {};

  // サマリー先読み制御
  final List<String> _summaryQueue = [];
  int _inflightSummaries = 0;
  static const int _maxConcurrentSummaries = 4;

  _StatusFilter _filter = _StatusFilter.unreviewedOnly;

  // ====== 小物ヘルパ ======
  void _log(String msg) {
    // ignore: avoid_print
    print('🔎 [AdminKYC] ${DateTime.now().toIso8601String()} $msg');
  }

  bool _isTrue(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  String _absUrl(String u) {
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (!u.startsWith('/')) return '$_host/$u';
    return '$_host$u';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.greenAccent.withOpacity(0.9);
      case 'rejected': return Colors.redAccent.withOpacity(0.9);
      default:         return Colors.orangeAccent.withOpacity(0.9); // pending/その他
    }
  }

  // ====== ライフサイクル ======
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMoreIds();
    });
  }

  // ====== API: ユーザID一覧（既存APIを再利用） ======
  Future<void> _loadMoreIds() async {
    if (_loadingIds) return;
    setState(() => _loadingIds = true);

    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      return;
    }

    final url = Uri.parse('$_host/admin/users/ids/?limit=$_pageSize&offset=$_offset');
    _log('GET $url');
    try {
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<String>();
        setState(() {
          _userIds.addAll(list);
          _offset += list.length;
        });
        _enqueueSummaries(list);
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
        if (await widget.auth.ensureTokenFromPrefs()) return _loadMoreIds();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ユーザー取得失敗: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通信エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingIds = false);
    }
  }

  // ====== サマリー先読み（KYC があるユーザーを上に） ======
  void _enqueueSummaries(List<String> ids) {
    _summaryQueue.addAll(ids);
    _pumpSummaryQueue();
  }

  void _pumpSummaryQueue() {
    if (_inflightSummaries >= _maxConcurrentSummaries) return;
    while (_inflightSummaries < _maxConcurrentSummaries && _summaryQueue.isNotEmpty) {
      final uid = _summaryQueue.removeAt(0);
      _fetchSummary(uid);
    }
  }

  Future<void> _fetchSummary(String userId) async {
    _inflightSummaries++;
    try {
      if (!await widget.auth.ensureTokenFromPrefs()) return;

      final url = Uri.parse('$_host/admin/kyc/images/$userId/?_ts=${DateTime.now().millisecondsSinceEpoch}');
      _log('GET (KYC summary) $url');
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (decoded is List)
            ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];

        // ★ /images/admin/<userId>/ のみ対象
        final filtered = list.where((m) {
          final u = (m['url'] as String?) ?? '';
          return _isAdminUserImagePath(userId, u);
        }).toList();
        final total = filtered.length;
        final unrev = filtered.where((e) => !_isTrue(e['reviewed'])).length;

        if (!mounted) return;
        setState(() {
          _totalCount[userId] = total;
          _unreviewedCount[userId] = unrev;
        });
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
      } else {
        _log('summary NG: user=$userId status=${res.statusCode}');
      }
    } catch (e) {
      _log('EX(fetchSummary:$userId): $e');
    } finally {
      _inflightSummaries--;
      _pumpSummaryQueue();
    }
  }

  // ====== 詳細取得（KYC画像） ======
  bool _isAdminUserImagePath(String userId, String url) {
    if (url.isEmpty) return false;
    final path = (url.startsWith('http://') || url.startsWith('https://'))
        ? Uri.parse(url).path
        : url; // 相対URLもOK
    if (!path.startsWith('/images/admin/')) return false;

    // 期待: /images/admin/<userId>/<filename>
    // ['', 'images', 'admin', '<userId>', '...']
    final seg = path.split('/');
    if (seg.length < 5) return false;
    return seg[3] == userId;
  }

  Future<void> _loadKycFor(String userId) async {
    if (_loadingUsers.contains(userId)) return;
    setState(() => _loadingUsers.add(userId));

    if (!await widget.auth.ensureTokenFromPrefs()) return;

    try {
      final url = Uri.parse('$_host/admin/kyc/images/$userId/?_ts=${DateTime.now().millisecondsSinceEpoch}');
      _log('GET (KYC images) $url');
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final raw = (decoded is List)
            ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];

        // ★ /images/admin/<userId>/ 以外は弾く → URL正規化 & reviewed正規化
        final resolved = <Map<String, dynamic>>[];
        for (final m in raw) {
          final urlRaw = (m['url'] as String?) ?? '';
          if (!_isAdminUserImagePath(userId, urlRaw)) continue; // ここで絞る
          final u = _absUrl(urlRaw);
          final r = _isTrue(m['reviewed']);
          resolved.add({...m, 'url': u, 'reviewed': r});
        }

        final total = resolved.length;
        final unrev = resolved.where((e) => !_isTrue(e['reviewed'])).length;

        setState(() {
          _kycByUser[userId] = resolved;
          _totalCount[userId] = total;
          _unreviewedCount[userId] = unrev;
        });
      } else if (res.statusCode == 401) {
        setState(() => _loadingUsers.remove(userId));
        widget.auth.token = null;
        if (await widget.auth.ensureTokenFromPrefs()) return _loadKycFor(userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KYC画像取得失敗: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通信エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUsers.remove(userId));
    }
  }

  Future<void> _delete(String userId, String filename) async {
    if (!await widget.auth.ensureTokenFromPrefs()) return;

    final url = Uri.parse('$_host/admin/kyc/images/$userId/${Uri.encodeComponent(filename)}');
    _log('DELETE $url');

    try {
      final res = await http.delete(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      if (res.statusCode == 200) {
        await _loadKycFor(userId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
        await _delete(userId, filename);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除失敗: ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除エラー: $e')),
        );
      }
    }
  }

  Future<void> _toggleReviewed(
    String userId,
    String filename,
    Map<String, dynamic> it, {
    bool? forceValue, // ★追加：明示的にこの値へセットしたいときに使う
  }) async {
    final current = _isTrue(it['reviewed']);
    final newVal = forceValue ?? !current; // forceValue があればそれを採用

    if (!await widget.auth.ensureTokenFromPrefs()) return;

    final url = Uri.parse(
      '$_host/admin/kyc/images/$userId/${Uri.encodeComponent(filename)}/reviewed/',
    );

    http.Response res;
    try {
      res = await http.post(
        url,
        headers: {
          ...widget.auth.authHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reviewed': newVal}),
      );
      if (res.statusCode == 405) {
        // PATCH フォールバック
        res = await http.patch(
          url,
          headers: {
            ...widget.auth.authHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'reviewed': newVal}),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通信エラー: トグルに失敗しました')),
        );
      }
      return;
    }

    if (res.statusCode == 401) {
      widget.auth.token = null;
      await _toggleReviewed(userId, filename, it, forceValue: forceValue);
      return;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // サーバー成功 → ローカル反映
      setState(() {
        final list = _kycByUser[userId];
        if (list != null) {
          final idx = list.indexWhere(
            (m) => (m['filename'] as String? ?? '') == filename,
          );
          if (idx >= 0) {
            list[idx] = {...list[idx], 'reviewed': newVal};
            _kycByUser[userId] = List<Map<String, dynamic>>.from(list);
          }
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗: ${res.statusCode}')),
        );
      }
    }
  }

  // image_index でグルーピング（KYCは #0=表 / #1=裏 などの想定）
  Map<int, List<Map<String, dynamic>>> _groupByIndex(List<Map<String, dynamic>> items) {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final idx = int.tryParse((it['image_index']?.toString() ?? '0')) ?? 0;
      map.putIfAbsent(idx, () => []).add(it);
    }
    return map;
  }

  // タイル（=同一 image_index グループ）を一括で確認/未確認にする
  Future<void> _toggleReviewedGroup(
    String userId,
    List<Map<String, dynamic>> group,
    bool toReviewed,
  ) async {
    // 楽観更新：まずUI
    setState(() {
      for (var i = 0; i < group.length; i++) {
        final g = group[i];
        group[i] = {...g, 'reviewed': toReviewed};
      }
    });

    // 各画像に対して “反転” ではなく “明示セット” を送る
    for (final g in group) {
      final filename = (g['filename'] as String?) ?? '';
      // fire-and-forget でOK（失敗時は後の再取得で補正）
      // ignore: unawaited_futures
      _toggleReviewed(userId, filename, g, forceValue: toReviewed);
    }

    // 真値で同期（軽い遅延を入れてバーストを避ける）
    // ignore: unawaited_futures
    Future.delayed(const Duration(milliseconds: 300), () => _loadKycFor(userId));
  }

  Future<void> _deleteUserFromKyc(String userId) async {
    // 確認ダイアログ
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('アカウント削除'),
        content: Text('本当に $userId を削除しますか？この操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除する')),
        ],
      ),
    );
    if (ok != true) return;

    // 認証確認（他タブと同じ流儀）
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return;
    }

    try {
      final uri = Uri.parse('$_kBase/admin/kyc/users/$userId/delete/');
      final res = await http.post(
        uri,
        headers: {
          ...widget.auth.authHeaders(),
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        // ローカルキャッシュからも除外（KYCタブの状態名に合わせて更新）
        setState(() {
          _kycByUser.remove(userId);       // ユーザー→KYC画像キャッシュ
          _totalCount.remove(userId);      // 総数サマリを持っている場合
          _unreviewedCount.remove(userId); // 未確認サマリを持っている場合
          _userIds.removeWhere((id) => id == userId); // リストから除外
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('アカウントを削除しました')),
        );
      } else if (res.statusCode == 401) {
        // トークン再取得→再試行
        widget.auth.token = null;
        await _deleteUserFromKyc(userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除失敗: ${res.statusCode} ${res.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通信エラー: $e')),
        );
      }
    }
  }

  // ====== フィルタ/並び順 ======
  bool _passesFilter(String userId) {
    final total = _totalCount[userId];
    final unrev = _unreviewedCount[userId];
    switch (_filter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.unreviewedOnly:
        // ★ 0枚も表示対象にする → 展開して「提出なし」を見せるため
        if (total == null || unrev == null) return true; // 未判定は表示
        if (total == 0) return true;
        return unrev > 0;                                // 未確認があるユーザー
      case _StatusFilter.allReviewed:
        if (total == null || unrev == null) return false;
        return total > 0 && unrev == 0;
    }
  }

  String _statusText(String userId) {
    final total = _totalCount[userId];
    final unrev = _unreviewedCount[userId];
    if (total == null || unrev == null) return '未確認';
    if (total == 0) return '画像なし';
    if (unrev == 0) return '全確認';
    return '未確認 $unrev';
  }

  List<String> _visibleSortedUserIds() {
    final filtered = _userIds.where(_passesFilter).toList();

    int score(String uid) {
      final t = _totalCount[uid];
      final u = _unreviewedCount[uid];
      if (t == null || u == null) return 1 << 20; // 未判定は上
      if (t == 0) return -1;                       // 画像なしは下
      if (u == 0) return 0;                        // 全確認は下の方
      return u;                                    // 未確認が多いほど上
    }

    filtered.sort((a, b) {
      final sa = score(a), sb = score(b);
      if (sa != sb) return sb.compareTo(sa);
      return a.compareTo(b);
    });
    return filtered;
  }

  Widget _statusChip(String userId) {
    final text = _statusText(userId);
    final color = _statusColor(userId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.9)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final ids = _visibleSortedUserIds();

    return Column(
      children: [
        // フィルタ
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('未確認のみ'),
                selected: _filter == _StatusFilter.unreviewedOnly,
                onSelected: (_) => setState(() => _filter = _StatusFilter.unreviewedOnly),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('確認済みのみ'),
                selected: _filter == _StatusFilter.allReviewed,
                onSelected: (_) => setState(() => _filter = _StatusFilter.allReviewed),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('すべて'),
                selected: _filter == _StatusFilter.all,
                onSelected: (_) => setState(() => _filter = _StatusFilter.all),
              ),
              const Spacer(),
              if (_loadingIds)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),

        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
                  !_loadingIds) {
                _loadMoreIds();
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ids.length + 1,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
              itemBuilder: (ctx, i) {
                if (i == ids.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingIds
                          ? const CircularProgressIndicator()
                          : TextButton(onPressed: _loadMoreIds, child: const Text('もっと読み込む')),
                    ),
                  );
                }
                final userId = ids[i];
                final items = _kycByUser[userId];

                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    collapsedIconColor: Colors.white70,
                    iconColor: Colors.white70,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            userId,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        _statusChip(userId),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'アカウント削除',
                          icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                          onPressed: () => _deleteUserFromKyc(userId),
                        ),
                      ],
                    ),
                    trailing: _loadingUsers.contains(userId)
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more, color: Colors.white70),
                    onExpansionChanged: (open) {
                      if (open && items == null) {
                        _loadKycFor(userId);
                      }
                    },
                    children: [
                      // ローディング
                      if (items == null && _loadingUsers.contains(userId))
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),

                      // 画像なし（=提出なし）でも展開表示
                      if (items != null && items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            '本人確認用書類の提出がありません',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),

                      // 画像あり：タイル（image_index）ごとにフル幅表示
                      if (items != null && items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Builder(
                            builder: (_) {
                              final groups = _groupByIndex(items);
                              final keys = groups.keys.toList()..sort();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final k in keys) ...[
                                    Builder(builder: (_) {
                                      final group = groups[k]!;
                                      final reviewedAll = group.every((e) => _isTrue(e['reviewed']));
                                      final status = ((group.first['moderation_status'] ?? 'pending') as String).toLowerCase();

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // --- タイル上部バー（KYC #index / ステータス / 一括トグル）---
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: _statusColor(status).withOpacity(0.18),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: _statusColor(status)),
                                                    ),
                                                    child: Text(
                                                      'KYC #$k • ${status.toUpperCase()}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  InkWell(
                                                    onTap: () => _toggleReviewedGroup(userId, group, !reviewedAll),
                                                    borderRadius: BorderRadius.circular(14),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: reviewedAll
                                                            ? Colors.green.withOpacity(0.85)
                                                            : Colors.black.withOpacity(0.55),
                                                        borderRadius: BorderRadius.circular(14),
                                                        border: Border.all(
                                                          color: reviewedAll ? Colors.greenAccent : Colors.white24,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            reviewedAll
                                                                ? Icons.check_circle
                                                                : Icons.radio_button_unchecked,
                                                            size: 16,
                                                            color: Colors.white,
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            reviewedAll ? '確認済み' : '未確認',
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // --- 同タイルの画像群：横幅いっぱいで縦並び（3:4想定） ---
                                            for (final it in group) ...[
                                              Stack(
                                                children: [
                                                  AspectRatio(
                                                    aspectRatio: 3 / 4,
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: _SmartNetImage(
                                                        url: (it['url'] as String?) ?? '',
                                                        fit: BoxFit.cover,
                                                        onError: (_) {},
                                                        onFallback: () {},
                                                      ),
                                                    ),
                                                  ),
                                                  // 各画像の削除（右上）
                                                  Positioned(
                                                    right: 6,
                                                    top: 6,
                                                    child: IconButton(
                                                      tooltip: 'この画像を削除',
                                                      icon: const Icon(Icons.delete_forever_rounded,
                                                          color: Colors.redAccent),
                                                      onPressed: () =>
                                                          _delete(userId, (it['filename'] as String?) ?? ''),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============ 写真タブ ============
class _AdminPhotosByUserTab extends StatefulWidget {
  final _AdminAuth auth;
  final _StatusFilter initialFilter;
  final bool showFilterChips;

  const _AdminPhotosByUserTab({
    required this.auth,
    this.initialFilter = _StatusFilter.unreviewedOnly,
    this.showFilterChips = true,
  });

  @override
  State<_AdminPhotosByUserTab> createState() => _AdminPhotosByUserTabState();
}

enum _StatusFilter { all, unreviewedOnly, allReviewed }

class _AdminPhotosByUserTabState extends State<_AdminPhotosByUserTab> {
  // ====== 設定 ======
  static const String _host = 'https://settee.jp';
  static const int _pageSize = 50;

  // ====== 状態 ======
  final List<String> _userIds = [];
  bool _loadingIds = false;
  int _offset = 0;

  // 展開時に使う詳細キャッシュ（各ユーザの画像配列）
  final Map<String, List<Map<String, dynamic>>> _photosByUser = {};
  final Set<String> _loadingUsers = {};

  // サマリー（総枚数 / 未確認枚数） → フィルタ＆ソートに使用
  final Map<String, int> _totalCount = {};
  final Map<String, int> _unreviewedCount = {};

  // サマリー先読み用のキュー（混雑緩和）
  final List<String> _summaryQueue = [];
  int _inflightSummaries = 0;
  static const int _maxConcurrentSummaries = 4;

  late _StatusFilter _filter;

  // ====== ライフサイクル ======
  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMoreIds();
    });
  }

  // ====== 小物ヘルパ ======
  void _log(String msg) {
    // 目視しやすい時刻つきログ
    // ignore: avoid_print
    print('🐞 [AdminPhotos] ${DateTime.now().toIso8601String()} $msg');
  }

  // サーバの reviewed が bool/num/string どれでも true/false に吸収
  bool _isTrue(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  // 画像 URL が相対なら https://settee.jp を補う
  String _absUrl(String u) {
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (!u.startsWith('/')) return '$_host/$u';
    return '$_host$u';
  }

  // ====== API: ユーザID一覧 ======
  Future<void> _loadMoreIds() async {
    if (_loadingIds) return;
    setState(() => _loadingIds = true);

    // /admin は必ず Bearer
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return;
    }

    final url = Uri.parse('$_host/admin/users/ids/?limit=$_pageSize&offset=$_offset');
    _log('GET $url');
    _log('→ headers(admin): ${widget.auth.authHeaders()}');

    try {
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      _log('← status=${res.statusCode} time=? bytes=${res.bodyBytes.length}');
      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<String>();
        _log('OK: fetched userIds=${list.length} (offset=$_offset)');
        setState(() {
          _userIds.addAll(list);
          _offset += list.length;
        });
        // ★ 各ユーザの画像を一度取得して reviewed を集計 → フィルタ/並び順に反映
        _enqueueSummaries(list);
      } else if (res.statusCode == 401) {
        // トークン再取得→再試行
        if (mounted) setState(() => _loadingIds = false);
        widget.auth.token = null;
        if (await widget.auth.ensureTokenFromPrefs()) {
          return _loadMoreIds();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ユーザー取得失敗: ${res.statusCode}')),
        );
      }
    } catch (e, st) {
      _log('EX(loadMoreIds): $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通信エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingIds = false);
    }
  }

  // ====== サマリー先読み（この結果でタブのリストを構成） ======
  void _enqueueSummaries(List<String> ids) {
    _summaryQueue.addAll(ids);
    _pumpSummaryQueue();
  }

  void _pumpSummaryQueue() {
    if (_inflightSummaries >= _maxConcurrentSummaries) return;
    while (_inflightSummaries < _maxConcurrentSummaries && _summaryQueue.isNotEmpty) {
      final uid = _summaryQueue.removeAt(0);
      _fetchSummary(uid);
    }
  }

  // /images/<userId>/ 配下だけを通す（/images/admin/... は除外）
  bool _isRootUserImagePath(String userId, String url) {
    if (url.isEmpty) return false;
    // 絶対URLなら path を取り出す
    final path = (url.startsWith('http://') || url.startsWith('https://'))
        ? Uri.parse(url).path
        : url;

    if (!path.startsWith('/images/')) return false;
    if (path.startsWith('/images/admin/')) return false; // 管理用は除外

    // 想定: /images/<userId>/<filename>
    final seg = path.split('/');
    // ['', 'images', '<userId>', '...']
    if (seg.length < 4) return false;
    return seg[2] == userId;
  }

  Future<void> _fetchSummary(String userId) async {
    _inflightSummaries++;
    try {
      if (!await widget.auth.ensureTokenFromPrefs()) return;

      final url = Uri.parse('$_host/admin/images/$userId/?_ts=${DateTime.now().millisecondsSinceEpoch}');
      _log('GET (summary) $url');
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (decoded is List)
            ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];

        // ★ /images/<userId>/ 直下だけ残す
        final filtered = list.where((m) {
          final u = (m['url'] as String?) ?? '';
          return _isRootUserImagePath(userId, u);
        }).toList();

        // reviewed を吸収しつつ集計
        final total = filtered.length;
        final unrev = filtered.where((e) => !_isTrue(e['reviewed'])).length;

        _log('summary: user=$userId total=$total unreviewed=$unrev');
        if (!mounted) return;
        setState(() {
          _totalCount[userId] = total;
          _unreviewedCount[userId] = unrev;
        });
      } else if (res.statusCode == 401) {
        // 認証切れ：次のポンプで再試行できるよう戻す必要はなし（都度 ensure 済）
        widget.auth.token = null;
      } else {
        _log('summary NG: user=$userId status=${res.statusCode}');
      }
    } catch (e, st) {
      _log('EX(fetchSummary:$userId): $e\n$st');
    } finally {
      _inflightSummaries--;
      _pumpSummaryQueue();
    }
  }

  // ====== ユーザ詳細（展開後に実画像URL＋reviewed正規化して保存） ======
  Future<void> _loadPhotosFor(String userId) async {
    if (_loadingUsers.contains(userId)) return;
    setState(() => _loadingUsers.add(userId));

    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return;
    }

    try {
      final url = Uri.parse('$_host/admin/images/$userId/?_ts=${DateTime.now().millisecondsSinceEpoch}');
      _log('GET (images) $url');
      final res = await http.get(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      _log('← (images) status=${res.statusCode} bytes=${res.bodyBytes.length}');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final raw = (decoded is List)
            ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];

        // URL 正規化 & reviewed を bool に寄せる
        final resolved = <Map<String, dynamic>>[];
        for (final m in raw) {
          final u = _absUrl((m['url'] as String?) ?? '');
          final r = _isTrue(m['reviewed']);
          resolved.add({...m, 'url': u, 'reviewed': r});
        }

        // 集計
        final total = resolved.length;
        final unrev = resolved.where((e) => !_isTrue(e['reviewed'])).length;
        _log('applyUserPhotos: user=$userId total=$total unreviewed=$unrev');

        setState(() {
          _photosByUser[userId] = resolved;
          _totalCount[userId] = total;
          _unreviewedCount[userId] = unrev;
        });
      } else if (res.statusCode == 401) {
        // 先にローディング解除して再試行可に
        if (mounted) setState(() => _loadingUsers.remove(userId));
        widget.auth.token = null;
        if (await widget.auth.ensureTokenFromPrefs()) {
          return _loadPhotosFor(userId);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像取得失敗: ${res.statusCode}')),
        );
      }
    } catch (e, st) {
      _log('EX(loadPhotosFor:$userId): $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像取得エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUsers.remove(userId));
    }
  }

  // 削除 → 再集計
  Future<void> _delete(String userId, String filename) async {
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return;
    }

    final url = Uri.parse('$_host/admin/images/$userId/${Uri.encodeComponent(filename)}');
    _log('DELETE $url');

    try {
      final res = await http.delete(url, headers: widget.auth.authHeaders());
      if (!mounted) return;

      if (res.statusCode == 200) {
        await _loadPhotosFor(userId); // 真値へ
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
        await _delete(userId, filename);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除失敗: ${res.statusCode}')),
        );
      }
    } catch (e, st) {
      _log('EX(delete): $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除エラー: $e')),
        );
      }
    }
  }

  // 確認済みトグル（POST → 405なら PATCH）＋ 楽観更新 ＋ 裏で再取得
  Future<void> _toggleReviewed(String userId, String filename, Map<String, dynamic> it) async {
    final current = _isTrue(it['reviewed']);
    final newVal = !current;
    if (!await widget.auth.ensureTokenFromPrefs()) return;

    final url = Uri.parse('$_host/admin/images/$userId/${Uri.encodeComponent(filename)}/reviewed/');
    _log('TOGGLE reviewed -> $newVal : $url');

    http.Response res;
    try {
      res = await http.post(
        url,
        headers: {...widget.auth.authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'reviewed': newVal}),
      );
      if (res.statusCode == 405) {
        _log('PATCH fallback');
        res = await http.patch(
          url,
          headers: {...widget.auth.authHeaders(), 'Content-Type': 'application/json'},
          body: jsonEncode({'reviewed': newVal}),
        );
      }
    } catch (e, st) {
      _log('EX(toggleReviewed): $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通信エラー: トグルに失敗しました')),
        );
      }
      return;
    }

    _log('← status=${res.statusCode} body=${res.body}');
    if (res.statusCode == 401) {
      widget.auth.token = null;
      await _toggleReviewed(userId, filename, it);
      return;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // 楽観更新
      setState(() {
        final list = _photosByUser[userId];
        if (list != null) {
          final idx = list.indexWhere((m) => (m['filename'] as String? ?? '') == filename);
          if (idx >= 0) {
            final updated = {...list[idx], 'reviewed': newVal};
            list[idx] = updated;
            _photosByUser[userId] = List<Map<String, dynamic>>.from(list);

            final total = list.length;
            final unrev = list.where((e) => !_isTrue(e['reviewed'])).length;
            _totalCount[userId] = total;
            _unreviewedCount[userId] = unrev;
          }
        }
      });

      // 背景で真値を再取得（UIは既に反映済み）
      // ignore: unawaited_futures
      _loadPhotosFor(userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newVal ? '確認済みにしました' : '未確認に戻しました')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗: ${res.statusCode}')),
        );
      }
    }
  }

  // ====== フィルタ／並び順 ======
  String _statusText(String userId) {
    final total = _totalCount[userId];
    final unrev = _unreviewedCount[userId];
    if (total == null || unrev == null) return '未確認'; // 未判定は未確認扱いで先に回す
    if (total == 0) return '画像なし';
    if (unrev == 0) return '全確認';
    return '未確認 $unrev';
  }

  Color _statusColor(String userId) {
    final total = _totalCount[userId];
    final unrev = _unreviewedCount[userId];
    if (total == null || unrev == null) return Colors.orangeAccent.withOpacity(0.9);
    if (total == 0) return Colors.white24;
    if (unrev == 0) return Colors.greenAccent.withOpacity(0.9);
    return Colors.orangeAccent.withOpacity(0.9);
  }

  bool _passesFilter(String userId) {
    final total = _totalCount[userId];
    final unrev = _unreviewedCount[userId];
    switch (_filter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.unreviewedOnly:
        if (total == null || unrev == null) return true; // 未判定は未確認扱いで表示
        return total > 0 && unrev > 0; // 1枚でも未確認がある
      case _StatusFilter.allReviewed:
        if (total == null || unrev == null) return false; // 未判定は除外
        return total > 0 && unrev == 0; // 全部確認済み
    }
  }

  List<String> _visibleSortedUserIds() {
    final filtered = _userIds.where(_passesFilter).toList();

    int score(String uid) {
      final t = _totalCount[uid];
      final u = _unreviewedCount[uid];
      if (t == null || u == null) return 1 << 20; // 未判定は最優先で上へ
      if (t == 0) return -1; // 画像なしは下へ
      if (u == 0) return 0;  // 全確認は下の方
      return u;              // 未確認枚数が多いほど上
    }

    filtered.sort((a, b) {
      final sa = score(a), sb = score(b);
      if (sa != sb) return sb.compareTo(sa);
      return a.compareTo(b);
    });
    return filtered;
  }

  Widget _statusChip(String userId) {
    final text = _statusText(userId);
    if (text.isEmpty) return const SizedBox.shrink();
    final color = _statusColor(userId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.9)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final ids = _visibleSortedUserIds();

    return Column(
      children: [
        if (widget.showFilterChips) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('未確認のみ'),
                  selected: _filter == _StatusFilter.unreviewedOnly,
                  onSelected: (_) => setState(() => _filter = _StatusFilter.unreviewedOnly),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('確認済みのみ'),
                  selected: _filter == _StatusFilter.allReviewed,
                  onSelected: (_) => setState(() => _filter = _StatusFilter.allReviewed),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('すべて'),
                  selected: _filter == _StatusFilter.all,
                  onSelected: (_) => setState(() => _filter = _StatusFilter.all),
                ),
                const Spacer(),
                if (_loadingIds) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
        ],

        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
                  !_loadingIds) {
                _loadMoreIds();
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ids.length + 1,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
              itemBuilder: (ctx, i) {
                if (i == ids.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingIds
                          ? const CircularProgressIndicator()
                          : TextButton(onPressed: _loadMoreIds, child: const Text('もっと読み込む')),
                    ),
                  );
                }
                final userId = ids[i];
                final photos = _photosByUser[userId];

                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    collapsedIconColor: Colors.white70,
                    iconColor: Colors.white70,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(userId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        _statusChip(userId),
                      ],
                    ),
                    trailing: _loadingUsers.contains(userId)
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more, color: Colors.white70),
                    onExpansionChanged: (open) {
                      _log('expand[$userId] -> $open (cached=${photos != null}, error=${_loadingUsers.contains(userId)})');
                      if (open && photos == null) {
                        _loadPhotosFor(userId); // 展開時に詳細を取得
                      }
                    },
                    children: [
                      if (photos == null && _loadingUsers.contains(userId))
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (photos != null && photos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('写真はありません', style: TextStyle(color: Colors.white70)),
                        ),
                      if (photos != null && photos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                            itemCount: photos.length,
                            itemBuilder: (_, idx) {
                              final it = photos[idx];
                              final reviewed = _isTrue(it['reviewed']);
                              final reportCount = (it['report_count'] as int?) ?? 0;

                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    (it['url'] as String?) ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
                                  ),
                                  Positioned(
                                    top: 4, right: 4,
                                    child: Row(
                                      children: [
                                        if (reportCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withOpacity(0.9),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '通報 $reportCount',
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                                          onPressed: () => _delete(userId, it['filename'] as String),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    left: 6, bottom: 6,
                                    child: InkWell(
                                      onTap: () => _toggleReviewed(userId, it['filename'] as String, it),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: reviewed ? Colors.green.withOpacity(0.85) : Colors.black.withOpacity(0.55),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: reviewed ? Colors.greenAccent : Colors.white24),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              reviewed ? Icons.check_circle : Icons.radio_button_unchecked,
                                              size: 16, color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              reviewed ? '確認済み' : '未確認',
                                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// ==========================
/// ネットワーク画像 → メモリ画像に自動フォールバック
/// ==========================
class _SmartNetImage extends StatefulWidget {
  final String url;
  final void Function(int frame, bool sync)? onFrameShown;
  final void Function(Object err)? onError;
  final VoidCallback? onFallback;
  final BoxFit fit;

  const _SmartNetImage({
    required this.url,
    this.onFrameShown,
    this.onError,
    this.onFallback,
    this.fit = BoxFit.cover,
  });

  @override
  State<_SmartNetImage> createState() => _SmartNetImageState();
}

class _SmartNetImageState extends State<_SmartNetImage> {
  Uint8List? _bytes;
  bool _gotFrame = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 1.4秒でフレームが来なければフォールバック
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (!_gotFrame && _bytes == null) {
        _fetchBytes();
      }
    });
  }

  Future<void> _fetchBytes() async {
    try {
      // 画像は /images/... で公開配信 → 認証不要
      final res = await http.get(Uri.parse(widget.url));
      if (res.statusCode == 200) {
        setState(() => _bytes = res.bodyBytes);
        widget.onFallback?.call();
      } else {
        widget.onError?.call('fallback http ${res.statusCode}');
      }
    } catch (e) {
      widget.onError?.call(e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit);
    }
    return Image.network(
      widget.url,
      fit: widget.fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && !_gotFrame) {
          _gotFrame = true;
          _timer?.cancel();
          widget.onFrameShown?.call(frame, wasSynchronouslyLoaded);
        }
        return child;
      },
      loadingBuilder: (c, child, prog) {
        if (prog == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (c, err, st) {
        widget.onError?.call(err);
        // 失敗時もフォールバック試行（未実行なら）
        if (_bytes == null) _fetchBytes();
        return const ColoredBox(color: Colors.black26);
      },
    );
  }
}


// ============ 通報 / BAN タブも Bearer ヘッダを使うよう差し替え ============

class _AdminReportsTab extends StatefulWidget {
  final _AdminAuth auth;
  const _AdminReportsTab({required this.auth});
  @override
  State<_AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<_AdminReportsTab> {
  bool loading = true;

  /// 集計リスト（ユーザー単位）
  /// 期待フィールド: user_id, nickname, report_count, unread_count
  List<Map<String, dynamic>> _agg = [];

  /// ユーザーごとの通報詳細キャッシュ
  /// key: user_id, value: List<report>
  final Map<String, List<Map<String, dynamic>>> _detailByUser = {};

  @override
  void initState() {
    super.initState();
    _fetchAgg();
  }

  Future<void> _fetchAgg() async {
    setState(() => loading = true);
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$_kBase/admin/users/reports/'),
        headers: widget.auth.authHeaders(),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        // unread_count が未提供でも 0 扱い
        for (final m in list) {
          m['unread_count'] = (m['unread_count'] as int?) ?? 0;
          m['report_count'] = (m['report_count'] as int?) ?? 0;
        }
        setState(() => _agg = list);
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
        await _fetchAgg();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通報集計の取得失敗: ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通信エラー: 通報集計の取得に失敗しました')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openUserReportsSheet(String userId, String nickname) async {
    // 詳細未取得なら取得
    if (!_detailByUser.containsKey(userId)) {
      final ok = await _fetchDetails(userId);
      if (!ok) return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      useSafeArea: true, // ノッチ/ステータスとかぶらない
      builder: (ctx) {
        final reports = _detailByUser[userId] ?? const [];
        final topInset = MediaQuery.of(ctx).padding.top;

        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: topInset + 8, // さらに余白を足す
            bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- ドラッグハンドル ---
              Container(
                width: 44, height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),

              // --- ヘッダ：戻る + タイトル + すべて既読 ---
              Row(
                children: [
                  // 戻る（モーダルを閉じる）
                  IconButton(
                    tooltip: '戻る',
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  const SizedBox(width: 4),
                  // タイトル
                  Expanded(
                    child: Text(
                      '$nickname（$userId）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  // すべて既読
                  TextButton.icon(
                    onPressed: () => _markAllRead(userId),
                    icon: const Icon(Icons.done_all, color: Colors.white70, size: 18),
                    label: const Text('すべて既読', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 6),

              // --- 明細 ---
              Expanded(
                child: ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final r = reports[i];
                    final read = (r['read'] as bool?) == true;
                    final reviewed = (r['reviewed'] as bool?) == true;
                    final createdAt = (r['created_at'] ?? '').toString();

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      leading: Stack(
                        children: [
                          Container(
                            width: 40, height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(Icons.flag_outlined, color: Colors.white70, size: 22),
                          ),
                          if (!read)
                            Positioned(
                              right: -1, top: -1,
                              child: Container(
                                width: 10, height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.orangeAccent, shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // 理由は表示しない
                      title: Text(
                        '通報',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: read ? FontWeight.normal : FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        createdAt,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (reviewed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.greenAccent.withOpacity(0.9)),
                              ),
                              child: const Text('確認済み', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '既読にする',
                            onPressed: read ? null : () => _markRead(userId, r['id']),
                            icon: Icon(Icons.mark_email_read_outlined,
                                color: read ? Colors.white24 : Colors.white70),
                          ),
                        ],
                      ),
                      onTap: () => _markRead(userId, r['id']),
                    );
                  },
                ),
              ),

              // --- 下部にも「閉じる」を用意しておくとさらに親切 ---
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('閉じる'),
                ),
              ),
            ],
          ),
        );
      },
    );

    // モーダルを閉じた後に集計を再計算（未読数反映）
    _recalcUnreadFromDetails(userId);
  }

  Future<bool> _fetchDetails(String userId) async {
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return false;
    }

    try {
      final uri = Uri.parse('$_kBase/admin/reports/?user_id=$userId');
      final res = await http.get(uri, headers: widget.auth.authHeaders());
      if (!mounted) return false;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() => _detailByUser[userId] = list);
        return true;
      } else if (res.statusCode == 401) {
        widget.auth.token = null;
        return await _fetchDetails(userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通報詳細の取得失敗: ${res.statusCode}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通信エラー: 通報詳細の取得に失敗しました')),
        );
      }
    }
    return false;
  }

  Future<void> _markRead(String userId, dynamic reportId) async {
    if (!await widget.auth.ensureTokenFromPrefs()) return;
    if (reportId == null) return;

    final uri = Uri.parse('$_kBase/admin/reports/$reportId/read/');
    http.Response res;

    try {
      res = await http.patch(
        uri,
        headers: {...widget.auth.authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'read': true}),
      );
      if (res.statusCode == 403 || res.statusCode == 405) {
        // フォールバック
        res = await http.post(
          uri,
          headers: {
            ...widget.auth.authHeaders(),
            'Content-Type': 'application/json',
            'X-HTTP-Method-Override': 'PATCH',
          },
          body: jsonEncode({'read': true}),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通信エラー: 既読化に失敗しました')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (res.statusCode == 200) {
      // ローカル詳細を更新
      final list = _detailByUser[userId];
      if (list != null) {
        final idx = list.indexWhere((e) => e['id'] == reportId);
        if (idx >= 0) {
          setState(() {
            list[idx] = {...list[idx], 'read': true};
          });
        }
      }
      _recalcUnreadFromDetails(userId);
    } else if (res.statusCode == 401) {
      widget.auth.token = null;
      await _markRead(userId, reportId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('既読化失敗: ${res.statusCode}')),
      );
    }
  }

  Future<void> _markAllRead(String userId) async {
    if (!await widget.auth.ensureTokenFromPrefs()) return;

    final uri = Uri.parse('$_kBase/admin/users/$userId/reports/read_all/');
    http.Response res;

    try {
      res = await http.post(
        uri,
        headers: {...widget.auth.authHeaders(), 'Content-Type': 'application/json'},
      );
      // 405 などの場合は、明細を一括でローカル既読化（サーバ未対応フォールバック）
      if (res.statusCode == 404 || res.statusCode == 405) {
        // ローカルで既読化してから集計再計算
        setState(() {
          final list = _detailByUser[userId];
          if (list != null) {
            for (var i = 0; i < list.length; i++) {
              list[i] = {...list[i], 'read': true};
            }
          }
        });
        _recalcUnreadFromDetails(userId);
        return;
      }
    } catch (_) {
      // サーバ障害時もローカル既読に倒して UX を守る（必要に応じて無効化可）
      setState(() {
        final list = _detailByUser[userId];
        if (list != null) {
          for (var i = 0; i < list.length; i++) {
            list[i] = {...list[i], 'read': true};
          }
        }
      });
      _recalcUnreadFromDetails(userId);
      return;
    }

    if (res.statusCode == 200) {
      // サーバ成功 → ローカル反映
      setState(() {
        final list = _detailByUser[userId];
        if (list != null) {
          for (var i = 0; i < list.length; i++) {
            list[i] = {...list[i], 'read': true};
          }
        }
      });
      _recalcUnreadFromDetails(userId);
    } else if (res.statusCode == 401) {
      widget.auth.token = null;
      await _markAllRead(userId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一括既読化失敗: ${res.statusCode}')),
      );
    }
  }

  void _recalcUnreadFromDetails(String userId) {
    final detail = _detailByUser[userId];
    if (detail == null) return;
    final unread = detail.where((e) => (e['read'] as bool?) != true).length;

    // 集計リストの該当ユーザーの unread_count を更新
    final idx = _agg.indexWhere((e) => e['user_id'] == userId);
    if (idx >= 0) {
      setState(() {
        final m = Map<String, dynamic>.from(_agg[idx]);
        m['unread_count'] = unread;
        _agg[idx] = m;
      });
    }
  }

  // 表示用：未読チップ
  Widget _unreadChip(int unreadCount) {
    if (unreadCount <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.9)),
        ),
        child: const Text('既読', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.9)),
      ),
      child: Text('未読 $unreadCount',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (_agg.isEmpty) {
      return const Center(child: Text('通報はありません', style: TextStyle(color: Colors.white70)));
    }

    // 未読が多い順にソート
    final list = [..._agg]..sort((a, b) {
      final ua = (a['unread_count'] as int?) ?? 0;
      final ub = (b['unread_count'] as int?) ?? 0;
      if (ua != ub) return ub.compareTo(ua);
      // 同数なら通報件数降順
      final ra = (a['report_count'] as int?) ?? 0;
      final rb = (b['report_count'] as int?) ?? 0;
      return rb.compareTo(ra);
    });

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
      itemBuilder: (_, i) {
        final u = list[i];
        final userId = (u['user_id'] ?? '').toString();
        final nickname = (u['nickname'] ?? '').toString();
        final reportCount = (u['report_count'] as int?) ?? 0;
        final unreadCount = (u['unread_count'] as int?) ?? 0;

        return ListTile(
          onTap: () => _openUserReportsSheet(userId, nickname),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '$nickname ($userId)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              _unreadChip(unreadCount),
            ],
          ),
          subtitle: Text('通報件数: $reportCount', style: const TextStyle(color: Colors.white70)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        );
      },
    );
  }
}

class _AdminBanTab extends StatefulWidget {
  final _AdminAuth auth;
  const _AdminBanTab({required this.auth});
  @override
  State<_AdminBanTab> createState() => _AdminBanTabState();
}

class _AdminBanTabState extends State<_AdminBanTab> {
  final idCtl = TextEditingController();
  bool loading = false;
  String? result;

  Future<void> _setBan(bool ban) async {
    if (idCtl.text.trim().isEmpty) return;
    setState(() { loading = true; result = null; });
    if (!await widget.auth.ensureTokenFromPrefs()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者トークンがありません。再ログインしてください')),
      );

      // Welcome に戻し、戻るボタンで戻れないようナビゲーションスタックをクリア
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
      return; // 以降の処理を止める
    }

    try {
      final res = await http.post(
        Uri.parse('$_kBase/admin/ban/'),
        headers: {...widget.auth.authHeaders(), 'Content-Type': 'application/json'},
        body: jsonEncode({'target_user_id': idCtl.text.trim(), 'ban': ban}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        result = ban ? 'BANしました' : 'BAN解除しました';
      } else if (res.statusCode == 401) {
        widget.auth.token = null; await _setBan(ban);
      } else {
        result = '失敗: ${res.statusCode} ${res.body}';
      }
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: idCtl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '対象ユーザーID', hintStyle: TextStyle(color: Colors.white38)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton(
                onPressed: loading ? null : () => _setBan(true),
                child: const Text('BANする'),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(
                onPressed: loading ? null : () => _setBan(false),
                child: const Text('BAN解除'),
              )),
            ],
          ),
          const SizedBox(height: 12),
          if (loading) const CircularProgressIndicator(),
          if (result != null) Text(result!, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
