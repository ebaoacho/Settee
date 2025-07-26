import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'welcome_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';


class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  UserProfileScreenState createState() => UserProfileScreenState();
}

class UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

  final Map<String, TextEditingController> _fields = {
    'user_id': TextEditingController(),
    'nickname': TextEditingController(),
    'birth_date': TextEditingController(),
    'occupation': TextEditingController(),
    'university': TextEditingController(),
    'blood_type': TextEditingController(),
    'height': TextEditingController(),
    'drinking': TextEditingController(),
    'smoking': TextEditingController(),
    'email': TextEditingController(),
    'password': TextEditingController(),
  };

  final List<String> bloodTypes = ['A型', 'B型', 'O型', 'AB型', '不明', '未設定'];
  final List<String> drinkingOptions = ['飲まない', 'ときどき飲む', 'よく飲む', '未設定'];
  final List<String> smokingOptions = ['吸わない', 'ときどき吸う', '吸う', '未設定'];
  final List<String> heights = ['未設定', ...List.generate(17, (i) => '${120 + i * 5}cm')];

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    final response = await http.get(Uri.parse('https://settee.jp/get-profile/${widget.userId}/'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        userData = data;
        _fields.forEach((key, controller) {
          controller.text = data[key] != null ? (data[key] is List ? data[key].join(', ') : data[key].toString()) : '未設定';
        });
        _fields['password']!.text = '';
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> updateUserProfile() async {
    final uri = Uri.parse('https://settee.jp/update-profile/${widget.userId}/');

    final updatedData = {
      for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
    };

    try {
      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updatedData),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィールを更新しました')),
        );
        await fetchUserProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新に失敗しました (${response.statusCode})')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  Widget buildInfoRow(String title, String fieldKey, {bool secure = false}) {
    final bool useDropdown = {
      'blood_type',
      'height',
      'drinking',
      'smoking'
    }.contains(fieldKey);

    final isDateField = fieldKey == 'birth_date';

    return GestureDetector(
      onTap: () async {
        String? updated;

        if (useDropdown) {
          List<String> options;
          switch (fieldKey) {
            case 'blood_type':
              options = bloodTypes;
              break;
            case 'drinking':
              options = drinkingOptions;
              break;
            case 'smoking':
              options = smokingOptions;
              break;
            case 'height':
              options = heights;
              break;
            default:
              options = [];
          }

          updated = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('$title を選択'),
              content: DropdownButton<String>(
                isExpanded: true,
                value: _fields[fieldKey]!.text,
                items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => Navigator.pop(context, val),
              ),
            ),
          );
        } else if (isDateField) {
          DateTime initial = DateTime.tryParse(_fields[fieldKey]!.text) ?? DateTime(2000);
          DateTime selectedDate = initial;

          await showModalBottomSheet(
            context: context,
            builder: (BuildContext context) {
              return Container(
                height: 250,
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    Expanded(
                      child: CupertinoDatePicker(
                        initialDateTime: initial,
                        minimumYear: 1960,
                        maximumYear: DateTime.now().year - 18,
                        mode: CupertinoDatePickerMode.date,
                        onDateTimeChanged: (DateTime date) {
                          selectedDate = date;
                        },
                      ),
                    ),
                    TextButton(
                      child: const Text("決定"),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              );
            },
          );

          updated =
              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
        } else {
          updated = await showDialog<String>(
            context: context,
            builder: (context) {
              final controller = TextEditingController(text: _fields[fieldKey]!.text);
              return AlertDialog(
                title: Text('$title を入力'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(hintText: '$title'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }

        if (updated != null && updated.isNotEmpty) {
          setState(() {
            _fields[fieldKey]!.text = updated!;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white)),
            Row(
              children: [
                Text(secure ? '********' : _fields[fieldKey]!.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_right, color: Colors.white)
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildImageGrid() {
    final userId = widget.userId;
    final supportedExtensions = ['jpg', 'jpeg', 'png'];

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
      itemBuilder: (context, index) {
        return FutureBuilder<String?>(
          future: _getExistingImageUrl(userId, index + 1, supportedExtensions),
          builder: (context, snapshot) {
            final imageUrl = snapshot.data;
            final exists = snapshot.connectionState == ConnectionState.done && imageUrl != null;

            return Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    exists
                        ? Image.network(imageUrl, fit: BoxFit.contain)
                        : Container(
                            color: Colors.black26,
                            child: const Icon(Icons.image_not_supported, color: Colors.white30, size: 40),
                          ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          exists ? Icons.edit : Icons.add,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _getExistingImageUrl(String userId, int index, List<String> extensions) async {
    for (final ext in extensions) {
      final url = 'https://settee.jp/images/$userId/${userId}_$index.$ext';
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          return url;
        }
      } catch (_) {}
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
          const Icon(Icons.person_outline, color: Colors.black),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.userId),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Image.asset('assets/white_logo_text.png', width: 90),
                    const SizedBox(height: 16),
                    const CircleAvatar(radius: 40, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white, size: 40)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(_fields['nickname']!.text, style: const TextStyle(color: Colors.white, fontSize: 18))
                      ],
                    ),
                    const SizedBox(height: 16),
                    buildImageGrid(),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('基本情報', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    buildInfoRow('ユーザー名（ID）', 'user_id'),
                    buildInfoRow('生年月日', 'birth_date'),
                    buildInfoRow('職業', 'occupation'),
                    buildInfoRow('大学名', 'university'),
                    buildInfoRow('血液型', 'blood_type'),
                    buildInfoRow('身長', 'height'),
                    buildInfoRow('お酒', 'drinking'),
                    buildInfoRow('煙草', 'smoking'),
                    const SizedBox(height: 16),
                    buildInfoRow('メールアドレス', 'email'),
                    buildInfoRow('パスワード', 'password', secure: true),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: updateUserProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      child: const Text('プロフィールを更新する'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('user_id');
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                      child: const Text('ログアウト'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}