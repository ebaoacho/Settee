import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'welcome_screen.dart';
import 'settings_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'paywall_screen.dart';


class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  UserProfileScreenState createState() => UserProfileScreenState();
}

class UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? profileImageUrl;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  int? _uploadingIndex; // 1〜9 のどれをアップ中か
  final Map<int, int> _cacheBuster = {}; // {index: epoch} キャッシュ回避用
  static const List<String> kSupportedImageExts = ['jpg', 'jpeg', 'png', 'heic', 'heif'];
  String? _phone;
  String? _email;

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
    'gender': TextEditingController(),
    'zodiac': TextEditingController(),
    'mbti': TextEditingController(),
    'seeking': TextEditingController(),
    'preference': TextEditingController(),
  };

  final List<String> bloodTypes = ['A型', 'B型', 'O型', 'AB型', '不明', '未設定'];
  final List<String> drinkingOptions = ['飲まない', 'ときどき飲む', 'よく飲む', '未設定'];
  final List<String> smokingOptions = ['吸わない', 'ときどき吸う', '吸う', '未設定'];
  final List<String> heights = ['未設定', ...List.generate(17, (i) => '${120 + i * 5}cm')];
  final List<String> genderOptions = ['未設定', '男性', '女性'];
  final List<String> zodiacOptions = [
    '未設定',
    'おひつじ座','おうし座','ふたご座','かに座','しし座','おとめ座',
    'てんびん座','さそり座','いて座','やぎ座','みずがめ座','うお座'
  ];
  final List<String> mbtiOptions = [
    '未設定',
    'INTJ','INTP','ENTJ','ENTP',
    'INFJ','INFP','ENFJ','ENFP',
    'ISTJ','ISFJ','ESTJ','ESFJ',
    'ISTP','ISFP','ESTP','ESFP'
  ];

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
    loadProfileImage();
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
        _phone = data['phone']?.toString(); 
        _email = data['email']?.toString();
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> loadProfileImage() async {
    final url = await _getExistingImageUrl(widget.userId, 1, kSupportedImageExts);

    if (mounted) {
      setState(() {
        profileImageUrl = url;
      });
    }
  }

  Future<void> _onTapImageSlot(int index, {required bool exists}) async {
    if (_isUploading) return;
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() { _isUploading = true; _uploadingIndex = index; });

    final uri = Uri.parse('https://settee.jp/upload-image/'); // ← 末尾スラッシュ必須
    final mime = lookupMimeType(picked.path) ?? 'application/octet-stream';
    final mediaType = MediaType.parse(mime);

    try {
      final req = http.MultipartRequest('POST', uri)
        ..fields['user_id'] = widget.userId
        ..fields['image_index'] = '$index'
        ..files.add(await http.MultipartFile.fromPath(
          'image',
          picked.path,
          filename: picked.name,     // サーバ側で content_type 優先で ext 決定
          contentType: mediaType,
        ));

      final streamRes = await req.send();
      final res = await http.Response.fromStream(streamRes);

      debugPrint('UPLOAD status: ${res.statusCode}');
      debugPrint('UPLOAD body: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() { _cacheBuster[index] = DateTime.now().millisecondsSinceEpoch; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像をアップロードしました')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: ${res.statusCode} ${res.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロードエラー: $e')));
    } finally {
      if (mounted) setState(() { _isUploading = false; _uploadingIndex = null; });
    }
  }

  // MIME から拡張子を決める（最低限）
  String _extFromMime(String mime, {String? fallbackFromPath}) {
    final lower = mime.toLowerCase();
    if (lower == 'image/png')  return '.png';
    if (lower == 'image/jpeg') return '.jpg';
    if (lower == 'image/heic') return '.heic';
    if (lower == 'image/heif') return '.heif';
    // MIMEが曖昧な場合は元のファイル拡張子を尊重
    if (fallbackFromPath != null) {
      final parts = fallbackFromPath.split('.');
      if (parts.length >= 2) {
        final ext = parts.last.toLowerCase();
        if (kSupportedImageExts.contains(ext)) return '.$ext';
      }
    }
    // 最終手段として jpg
    return '.jpg';
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

  Future<void> _editNickname() async {
    final current = _fields['nickname']!.text == '未設定' ? '' : _fields['nickname']!.text;
    final controller = TextEditingController(text: current);

    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ニックネームを編集'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20, // 必要に応じて調整
          decoration: const InputDecoration(
            hintText: 'ニックネーム',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (updated != null) {
      if (updated.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ニックネームを入力してください')));
        return;
      }
      setState(() {
        _fields['nickname']!.text = updated;
      });

      // すぐサーバ保存したい場合は下行を有効化
      // await updateUserProfile();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ニックネームを更新しました（未保存）')));
    }
  }

  Widget buildInfoRow(String title, String fieldKey, {bool secure = false}) {
    final bool useDropdown = {
      'blood_type',
      'height',
      'drinking',
      'smoking',
      'gender',
      'zodiac',
      'mbti',
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
            case 'gender':
              options = genderOptions;
              break;
            case 'zodiac':
              options = zodiacOptions;
              break;
            case 'mbti':
              options = mbtiOptions;
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
    final supportedExtensions = kSupportedImageExts;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
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
                      child: GestureDetector(
                        onTap: () {
                          _onTapImageSlot(index + 1, exists: exists);
                        },
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
      final url = 'https://settee.jp/images/$userId/${userId}_$index.$ext'
            '${_cacheBuster[index] != null ? '?t=${_cacheBuster[index]}' : ''}';

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
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),  // アイコンを少し上に配置
              child: const Icon(Icons.person, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    userId: widget.userId,
                    phoneNumber: _phone ?? '',
                    email: _email ?? '',
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
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
                    profileImageUrl != null
                      ? CircleAvatar(
                          radius: 40,
                          backgroundImage: NetworkImage(profileImageUrl!),
                        )
                      : const CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person, color: Colors.white, size: 40),
                        ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _editNickname,
                          child: const Icon(Icons.edit, color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _fields['nickname']!.text,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    buildInfoRow('性別', 'gender'), 
                    buildInfoRow('職業', 'occupation'),
                    buildInfoRow('学校名（学生の場合）', 'university'),
                    buildInfoRow('星座', 'zodiac'),
                    buildInfoRow('MBTI', 'mbti'),
                    buildInfoRow('血液型', 'blood_type'),
                    buildInfoRow('身長', 'height'),
                    buildInfoRow('お酒', 'drinking'),
                    buildInfoRow('煙草', 'smoking'),
                    buildInfoRow('求めているのは', 'seeking'),
                    buildInfoRow('好み', 'preference'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: updateUserProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      child: const Text('プロフィールを更新する'),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.8, // 画面幅の8割
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PaywallScreen(userId: widget.userId)),
                              );
                            },
                            child: Ink(
                              decoration: BoxDecoration(
                                // 上品な白〜ごく薄いグレーのグラデーション
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                // ごく薄い縁取りで引き締め
                                border: Border.all(color: Colors.black.withOpacity(0.06), width: 1),
                                // 柔らかいシャドウ
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.9),
                                    blurRadius: 2,
                                    spreadRadius: -1,
                                    offset: const Offset(0, -1),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Setteeをアップグレードする',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.chevron_right, size: 20, color: Colors.black.withOpacity(0.7)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/logo.png',
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/white_logo_text.png',
                              width: 100,
                              height: 30,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}