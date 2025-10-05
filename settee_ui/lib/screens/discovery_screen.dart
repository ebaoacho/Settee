import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'user_profile_screen.dart';
import 'profile_browse_screen.dart';
import 'matched_users_screen.dart';
import 'point_exchange_screen.dart';
import 'users_section_detail_screen.dart';
import 'paywall_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  final String userId;
  const DiscoveryScreen({super.key, required this.userId});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  int _setteePoints = 0;
  bool _pointsLoading = true;
  List<dynamic> _likers = [];
  bool _likersLoading = true;
  List<dynamic> popularUsers = [];
  List<dynamic> newUsers = [];
  String? gender;
  bool _setteeLikersActive = false;
  String _membershipPlan = 'free';

  @override
  void initState() {
    super.initState();
    fetchUsers();
    _fetchEntitlementsAndPoints();
  }

  Future<void> _fetchEntitlementsAndPoints() async {
    setState(() => _pointsLoading = true); // ヘッダのローディング
    final uri = Uri.parse('https://settee.jp/users/${widget.userId}/entitlements/');

    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;

        // ---- Point ----
        final dynamic p = j['settee_points'];
        final int points = switch (p) {
          int v => v,
          String s => int.tryParse(s) ?? 0,
          _ => 0,
        };

        // ---- プラン判定（active フラグ or until のフォールバック）----
        final now = DateTime.now();

        final sVip  = j['settee_vip_until']  as String?;
        final sPlus = j['settee_plus_until'] as String?;
        final vipUntil  = sVip  == null ? null : DateTime.tryParse(sVip);
        final plusUntil = sPlus == null ? null : DateTime.tryParse(sPlus);

        final bool vipActive = (j['settee_vip_active']  ?? false) as bool ||
            (vipUntil  != null && vipUntil.isAfter(now));
        final bool plusActive = (j['settee_plus_active'] ?? false) as bool ||
            (plusUntil != null && plusUntil.isAfter(now));

        final String plan = vipActive ? 'vip' : (plusActive ? 'plus' : 'free');

        if (!mounted) return;
        setState(() {
          _setteePoints = points;

          // “ロック解除フラグ”をプランで決定：plus/vip -> true, free -> false
          _setteeLikersActive = plan != 'free';

          // プラン保持（必要に応じてUI出し分けで利用可能）
          _membershipPlan = plan;

          _pointsLoading = false;

          // likers ローディングは plan によって決める
          _likersLoading = plan != 'free';
        });

        // ---- plus か vip の場合のみ “あなたをLikeしているユーザー” を解放（取得）----
        if (plan != 'free') {
          await _fetchLikers();
        } else {
          if (!mounted) return;
          setState(() => _likersLoading = false);
        }
      } else {
        if (!mounted) return;
        setState(() {
          _pointsLoading = false;
          _likersLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pointsLoading = false;
        _likersLoading = false;
      });
    }
  }

  Future<void> _fetchLikers() async {
    try {
      final res = await http.get(
        Uri.parse('https://settee.jp/liked-users/${widget.userId}/'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _likers = list;
          _likersLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _likersLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _likersLoading = false);
    }
  }

  Future<void> fetchUsers() async {
    try {
      final profileRes = await http.get(Uri.parse('https://settee.jp/get-profile/${widget.userId}/'));
      if (profileRes.statusCode == 200) {
        final profile = json.decode(profileRes.body);
        setState(() {
          gender = profile['gender'];
        });
      }

      final res1 = await http.get(Uri.parse('https://settee.jp/popular-users/${widget.userId}'));
      final res2 = await http.get(Uri.parse('https://settee.jp/recent-users/${widget.userId}'));

      if (res1.statusCode == 200 && res2.statusCode == 200) {
        setState(() {
          popularUsers = json.decode(res1.body);
          newUsers = json.decode(res2.body);
        });
      } else {
        debugPrint('API取得に失敗しました');
      }
    } catch (e) {
      debugPrint('通信エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 性別が取得できるまでローディング
    if (gender == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 性別によって画像を選択
    final isFemale = gender == '女性';
    // final yourTypeImage = isFemale ? 'assets/maybe_your_type_for_female.png' : 'assets/maybe_your_type.png';
    final likedYouImage = isFemale ? 'assets/liked_you_for_female.png' : 'assets/liked_you.png';

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.userId),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),

              // あなたをLikeしているユーザー
              _setteeLikersActive
                ? _buildLikersSection(
                    'あなたをLikeしているユーザー',
                    _likers,
                    loading: _likersLoading,
                    onHeaderTap: _likersLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UsersSectionDetailScreen(
                                  title: 'あなたをLikeしているユーザー',
                                  currentUserId: widget.userId,
                                  users: _likers, // サーバからの配列をそのまま渡す
                                ),
                              ),
                            );
                          },
                  )
                : _buildLockedSectionWithImage(
                    title: 'あなたをLikeしているユーザー',
                    imagePath: likedYouImage,
                  ),

              const SizedBox(height: 32),

              // 人気のユーザー（見出しタップで10件ページへ）
              _buildUserSection(
                '人気のユーザー',
                popularUsers,
                onHeaderTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UsersSectionDetailScreen(
                        title: '人気のユーザー',
                        currentUserId: widget.userId,
                        users: popularUsers, // サーバからの10件をそのまま渡す
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // 最近はじめたユーザー（見出しタップで10件ページへ）
              _buildUserSection(
                '最近はじめたユーザー',
                newUsers,
                onHeaderTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UsersSectionDetailScreen(
                        title: '最近はじめたユーザー',
                        currentUserId: widget.userId,
                        users: newUsers,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Image.asset('assets/white_logo_text.png', width: 90),
        Row(
          children: [
            // 表示：Settee Point 残高
            _pointsLoading
                ? const SizedBox(
                    width: 80,
                    height: 16,
                    child: LinearProgressIndicator(minHeight: 4),
                  )
                : Text(
                    'Settee Point  $_setteePoints p',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
            const SizedBox(width: 8),

            // 交換ボタン → 交換画面から戻ったら残高を再取得
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PointExchangeScreen(userId: widget.userId),
                  ),
                );
                if (!mounted) return;
                setState(() => _pointsLoading = true);
                _fetchEntitlementsAndPoints();
              },
              child: const Text('Pointを交換する', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLikersSection(
    String title,
    List<dynamic> users, {
    bool loading = false,
    VoidCallback? onHeaderTap, // ← 追加
  }) {
    if (loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              const SizedBox(
                width: 64,
                height: 14,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (users.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダはタップ可（空でも一覧に飛ばしたいなら onHeaderTap を渡す）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onHeaderTap,
            child: Row(
              children: const [
                Text(
                  'あなたをLikeしているユーザー',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Spacer(),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'いまは表示できる相手がいません。時間をおいて再度ご確認ください。',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    // popular/new の表示を転用（= 上位3件の横スクロール）
    return _buildUserSection(
      title,
      users,
      onHeaderTap: onHeaderTap, // ← ここも渡す
    );
  }

  Widget _buildLockedSectionWithImage({required String title, required String imagePath}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaywallScreen(
              userId: widget.userId,
              campaignActive: true, // リリース後は判定ロジックに置換
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.lock, color: Colors.white, size: 16),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Settee+以上限定です',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSection(
    String title,
    List<dynamic> users, {
    VoidCallback? onHeaderTap, // ← 追加
  }) {
    final supportedExtensions = ['jpg', 'jpeg', 'png'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onHeaderTap,
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          height: 220,
          child: Align(
            alignment: Alignment.center,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: users.length.clamp(0, 3),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final user = users[index];
                final userId = user['user_id'];
                return FutureBuilder<String?>(
                  future: _getExistingImageUrl(userId, 1, supportedExtensions),
                  builder: (context, snapshot) {
                    final imageUrl = snapshot.data;
                    return Container(
                      width: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AspectRatio(
                                aspectRatio: 9 / 16,
                                child: imageUrl != null
                                    ? Image.network(imageUrl, fit: BoxFit.contain)
                                    : const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.only(bottom: 6),
                            alignment: Alignment.center,
                            child: Text(
                              user['nickname'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<String?> _getExistingImageUrl(String userId, int index, List<String> extensions) async {
    for (final ext in extensions) {
      final url = 'https://settee.jp/images/$userId/${userId}_1.$ext';
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          return url;
        }
      } catch (_) {
        // 無視して次の拡張子へ
      }
    }
    return null;
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
            onTap: () {},
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchedUsersScreen(userId: userId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.mail_outline, color: Colors.black),
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
