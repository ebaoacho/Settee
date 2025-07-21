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

  @override
  void initState() {
    super.initState();
    fetchMatchedUsers();
  }

  Future<void> fetchMatchedUsers() async {
    final url = Uri.parse('http://10.0.2.2:8000/matched-users/${widget.userId}/');

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
                      final user = matchedUsers[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.white54,
                          radius: 24,
                        ),
                        title: Text(
                          user['nickname'],
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                currentUserId: widget.userId,
                                matchedUserId: user['user_id'],
                                matchedUserNickname: user['nickname'],
                              ),
                            ),
                          );
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DiscoveryScreen(userId: userId),
                ),
              );
            },
            child: const Icon(Icons.search, color: Colors.black),
          ),
          Image.asset('assets/logo_text.png', width: 70),
          GestureDetector(
            onTap: () {},
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
