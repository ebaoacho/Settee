import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_browse_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'profile_preview_screen.dart';
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

  // ====== 固定候補 ======
  final List<String> bloodTypes = ['未設定', 'A型', 'B型', 'O型', 'AB型', '不明'];
  final List<String> drinkingOptions = ['未設定', '飲まない', 'ときどき飲む', 'よく飲む'];
  final List<String> smokingOptions = ['未設定', '吸わない', 'ときどき吸う', '吸う'];
  static const int kMinHeightCm = 120;  // 必要に応じて調整
  static const int kMaxHeightCm = 220;  // 必要に応じて調整

  static final List<String> heights = [
    '未設定',
    ...List.generate(kMaxHeightCm - kMinHeightCm + 1, (i) => '${kMinHeightCm + i}cm'),
  ];
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

  // ご要望の選択肢
  final List<String> occupationOptions = [
    '未設定', '大学生', '短大', '専門学生', '社会人', 'フリーター',
  ];
  final List<String> seekingOptions = [
    '未設定', '恋人がほしい', '友達がほしい', '暇つぶし', 'チャット相手', 'まだわからない',
  ];
  final List<String> preferenceOptions = [
    '未設定',
    'まずは気軽に会いたい',
    '仲良くなってから会いたい',
    'グループで会いたい（2：2など）',
    '電話してから会いたい',
  ];

  // 編集不可フィールド
  final Set<String> _lockedFields = {'birth_date', 'gender'};

  // MBTIコードを表示用文字列に変換（例: INTJ → INTJ（建築家））
  String _formatMbtiDisplay(String mbti) {
    final Map<String, String> mbtiNames = {
      'INTJ': 'INTJ（建築家）',
      'INTP': 'INTP（論理学者）',
      'ENTJ': 'ENTJ（指揮官）',
      'ENTP': 'ENTP（討論者）',
      'INFJ': 'INFJ（提唱者）',
      'INFP': 'INFP（仲介者）',
      'ENFJ': 'ENFJ（主人公）',
      'ENFP': 'ENFP（広報運動家）',
      'ISTJ': 'ISTJ（管理者）',
      'ISFJ': 'ISFJ（擁護者）',
      'ESTJ': 'ESTJ（幹部）',
      'ESFJ': 'ESFJ（領事官）',
      'ISTP': 'ISTP（巨匠）',
      'ISFP': 'ISFP（冒険家）',
      'ESTP': 'ESTP（起業家）',
      'ESFP': 'ESFP（エンターテイナー）',
    };
    return mbtiNames[mbti] ?? mbti;
  }

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
          controller.text = data[key] != null
              ? (data[key] is List ? data[key].join(', ') : data[key].toString())
              : '未設定';
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

    final uri = Uri.parse('https://settee.jp/upload-image/'); // 末尾スラッシュ必須
    final mime = lookupMimeType(picked.path) ?? 'application/octet-stream';
    final mediaType = MediaType.parse(mime);

    try {
      final req = http.MultipartRequest('POST', uri)
        ..fields['user_id'] = widget.userId
        ..fields['image_index'] = '$index'
        ..files.add(await http.MultipartFile.fromPath(
          'image',
          picked.path,
          filename: picked.name,
          contentType: mediaType,
        ));

      final streamRes = await req.send();
      final res = await http.Response.fromStream(streamRes);

      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() { _cacheBuster[index] = DateTime.now().millisecondsSinceEpoch; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像をアップロードしました')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: ${res.statusCode} ${res.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロードエラー: $e')));
      }
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
    if (fallbackFromPath != null) {
      final parts = fallbackFromPath.split('.');
      if (parts.length >= 2) {
        final ext = parts.last.toLowerCase();
        if (kSupportedImageExts.contains(ext)) return '.$ext';
      }
    }
    return '.jpg';
  }

  Future<void> updateUserProfile() async {
    final uri = Uri.parse('https://settee.jp/update-profile/${widget.userId}/');

    // 送信データ生成（ロック項目は除外）
    final updatedData = <String, dynamic>{
      for (final entry in _fields.entries)
        if (!_lockedFields.contains(entry.key)) entry.key: entry.value.text.trim(),
    };

    try {
      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updatedData),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('プロフィールを更新しました')),
          );
        }
        await fetchUserProfile();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新に失敗しました (${response.statusCode})')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    }
  }

  Future<void> _editNickname() async {
    final current = _fields['nickname']!.text == '未設定' ? '' : _fields['nickname']!.text;
    final controller = TextEditingController(text: current);

    final updated = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ニックネームを編集',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 20,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'ニックネーム',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('キャンセル', style: TextStyle(fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, controller.text.trim()),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      ),
                      child: const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (updated != null) {
      if (updated.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ニックネームを入力してください')));
        }
        return;
      }
      setState(() {
        _fields['nickname']!.text = updated;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ニックネームを更新しました（未保存）')));
      }
    }
  }

  Widget buildInfoRow(String title, String fieldKey, {bool secure = false}) {
    final bool isLocked = _lockedFields.contains(fieldKey);
    final bool isHeightField = fieldKey == 'height';
    final bool isDateField = fieldKey == 'birth_date';

    // デフォルトのプルダウン対象（height はダイヤル処理のため除外するが含まれていても影響なし）
    final bool useDropdown = {
      'blood_type',
      'drinking',
      'smoking',
      'gender',
      'zodiac',
      'mbti',
      'occupation',
      'seeking',
      'preference',
    }.contains(fieldKey);

    return GestureDetector(
      onTap: () async {
        if (isLocked) return; // 編集不可

        String? updated;

        // ===== 身長：ダイヤル =====
        if (isHeightField) {
          int selectedIndex = heights.indexOf(_fields[fieldKey]!.text);
          if (selectedIndex < 0) {
            final fallback = heights.indexOf('170cm');
            selectedIndex = fallback >= 0 ? fallback : 0;
          }
          final controller = FixedExtentScrollController(initialItem: selectedIndex);

          await showModalBottomSheet(
            context: context,
            backgroundColor: Colors.black,
            builder: (context) {
              return SafeArea(
                child: Container(
                  height: 300,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      const Text('身長を選択', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: controller,
                          itemExtent: 36,
                          magnification: 1.12,
                          useMagnifier: true,
                          backgroundColor: Colors.black,
                          onSelectedItemChanged: (_) {},
                          children: heights
                              .map((h) => Center(child: Text(h, style: const TextStyle(color: Colors.white))))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('決定', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
          updated = heights[controller.selectedItem];
        }
        // ===== プルダウン系 =====
        else if (useDropdown) {
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
            case 'gender':
              options = genderOptions; // ロックされているので基本タップ不可
              break;
            case 'zodiac':
              options = zodiacOptions;
              break;
            case 'mbti':
              options = mbtiOptions;
              break;
            case 'occupation':
              options = occupationOptions;
              break;
            case 'seeking':
              options = seekingOptions;
              break;
            case 'preference':
              options = preferenceOptions;
              break;
            default:
              options = const [];
          }

          updated = await showDialog<String>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.85),
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title を選択',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: Column(
                          children: options.map((option) {
                            final isSelected = _fields[fieldKey]!.text == option;
                            final displayText = fieldKey == 'mbti' ? _formatMbtiDisplay(option) : option;
                            return InkWell(
                              onTap: () => Navigator.pop(context, option),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.15),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      displayText,
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white,
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check, color: Colors.black, size: 18),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: const Text('キャンセル', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        // ===== 日付（生年月日）: ロック済みなので通常は到達しないが念のため既存処理を温存 =====
        else if (isDateField) {
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
        }
        // ===== テキスト入力 =====
        else {
          updated = await showDialog<String>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.85),
            builder: (context) {
              final controller = TextEditingController(text: _fields[fieldKey]!.text);
              return Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title を入力',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: title,
                            hintStyle: const TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white54,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('キャンセル', style: TextStyle(fontSize: 15)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextButton(
                              onPressed: () => Navigator.pop(context, controller.text),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                              ),
                              child: const Text('OK', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                Text(
                  secure
                      ? '********'
                      : fieldKey == 'mbti'
                          ? _formatMbtiDisplay(_fields[fieldKey]!.text)
                          : _fields[fieldKey]!.text,
                  style: TextStyle(
                    color: isLocked ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 9:16のアスペクト比で3つ横に並べる
        final totalWidth = constraints.maxWidth;
        final spacing = 8.0;
        final itemWidth = (totalWidth - spacing * 4) / 3; // 左右と間の余白を考慮
        final itemHeight = itemWidth * (16 / 9); // 9:16のアスペクト比

        return SizedBox(
          height: itemHeight + spacing * 2,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(spacing),
            itemCount: 3,
            itemBuilder: (context, index) {
              return FutureBuilder<String?>(
                future: _getExistingImageUrl(userId, index + 1, supportedExtensions),
                builder: (context, snapshot) {
                  final imageUrl = snapshot.data;
                  final exists = snapshot.connectionState == ConnectionState.done && imageUrl != null;

                  return Container(
                    width: itemWidth,
                    height: itemHeight,
                    margin: EdgeInsets.only(right: index < 2 ? spacing : 0),
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
                              ? Image.network(imageUrl, fit: BoxFit.cover, width: itemWidth, height: itemHeight)
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
          ),
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

  Route<T> _noAnimRoute<T>(Widget page) => PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, __, ___, child) => child,
        maintainState: false,
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
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.home_outlined, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(DiscoveryScreen(userId: userId)),
                (route) => false,
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.search, color: Colors.black),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 10.0),
            child: Image(
              image: AssetImage('assets/logo_text.png'),
              width: 70,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                _noAnimRoute(MatchedUsersScreen(userId: userId)),
                (route) => false,
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.mail_outline, color: Colors.black),
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Icon(Icons.person, color: Colors.black),
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
          ? Center(
              child: Image.asset(
                'assets/loading_logo.gif',
                width: 80,
                height: 80,
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Image.asset('assets/white_logo_text.png', width: 120),
                    const SizedBox(height: 48),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 右上にプレビューボタン（グリッドと非重なり）
                          Row(
                            children: [
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ProfilePreviewScreen(
                                        userId: widget.userId,
                                        nickname: _fields['nickname']!.text,
                                        birthDateText: _fields['birth_date']!.text,
                                        gender: _fields['gender']!.text,
                                        mbti: _fields['mbti']!.text,
                                        drinking: _fields['drinking']!.text,
                                        zodiac: _fields['zodiac']!.text,
                                        university: _fields['university']!.text,
                                        smoking: _fields['smoking']!.text,
                                        occupation: _fields['occupation']!.text,
                                        height: _fields['height']!.text,
                                        seeking: _fields['seeking']!.text,
                                        preference: _fields['preference']!.text,
                                        selectedAreas: (userData?['selected_area'] as List?)?.cast<String>(),
                                        availableDates: (userData?['available_dates'] as List?)?.cast<String>(),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.visibility_outlined, size: 16),
                                label: const Text('プレビュー', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8), // ← ボタンとグリッドの間隔

                          // 既存のグリッド
                          buildImageGrid(),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('基本情報', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    buildInfoRow('ユーザー名（ID）', 'user_id'),
                    buildInfoRow('生年月日', 'birth_date'),         // ロック
                    buildInfoRow('性別', 'gender'),                 // ロック
                    buildInfoRow('職業', 'occupation'),
                    buildInfoRow('学校名（学生の場合）', 'university'),
                    buildInfoRow('星座', 'zodiac'),
                    buildInfoRow('MBTI', 'mbti'),
                    buildInfoRow('血液型', 'blood_type'),
                    buildInfoRow('身長', 'height'),                 // ダイヤル
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
                        widthFactor: 0.8,
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
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.black26, width: 1),
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
