import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'user_profile_screen.dart';
import 'profile_browse_screen.dart';
import 'matched_users_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  final String userId;
  const DiscoveryScreen({super.key, required this.userId});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final int myPoint = 10;
  List<dynamic> popularUsers = [];
  List<dynamic> newUsers = [];
  String? gender;

  @override
  void initState() {
    super.initState();
    fetchUsers();
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
    final yourTypeImage = isFemale ? 'assets/maybe_your_type_for_female.png' : 'assets/maybe_your_type.png';
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
              _buildSectionWithImage(
                title: 'あなたの好みかも',
                imagePath: yourTypeImage,
              ),
              const SizedBox(height: 32),
              _buildSectionWithImage(
                title: 'あなたをLikeしているユーザー',
                imagePath: likedYouImage,
              ),
              const SizedBox(height: 32),
              _buildUserSection('人気のユーザー', popularUsers),
              const SizedBox(height: 32),
              _buildUserSection('最近はじめたユーザー', newUsers),
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
            Text('MyPoint  $myPoint',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () {},
              child: const Text('Pointを交換する', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionWithImage({required String title, required String imagePath}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.lock, color: Colors.white, size: 16),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
        const SizedBox(height: 2),
        const Text('Settee+以上限定です', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(imagePath, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }

  Widget _buildUserSection(String title, List<dynamic> users) {
    final supportedExtensions = ['jpg', 'jpeg', 'png'];

    return Column(
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
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: Align(
            alignment: Alignment.center,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: users.length.clamp(0, 3), // 最大3人まで
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
                          // 白背景内に「余白つき」で画像を収める
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
        final response = await http.head(Uri.parse(url));
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
      height: 60,
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
            child: const Icon(Icons.home_outlined, color: Colors.black),
          ),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.search, color: Colors.black),
          ),
          Image.asset('assets/logo_text.png', width: 70),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchedUsersScreen(userId: userId),
                ),
              );
            },
            child: const Icon(Icons.send_outlined, color: Colors.black),
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
            child: const Icon(Icons.person_outline, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
