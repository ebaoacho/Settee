import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'user_profile_screen.dart';
import 'discovery_screen.dart';
import 'matched_users_screen.dart';
import 'area_selection_screen.dart';

class ProfileBrowseScreen extends StatefulWidget {
  final String currentUserId;
  final bool showTutorial;

  const ProfileBrowseScreen({super.key, required this.currentUserId, this.showTutorial = false});

  @override
  State<ProfileBrowseScreen> createState() => _ProfileBrowseScreenState();
}

class _ProfileBrowseScreenState extends State<ProfileBrowseScreen> {
  List<Map<String, dynamic>> profiles = [];
  Map<String, Map<int, String>> userImageUrls = {};
  Map<String, int> imageIndexes = {};
  final PageController _pageController = PageController();
  bool isFetching = false;
  bool isLoading = true;
  bool? isMatchMultiple;
  int currentPageIndex = 0;
  List<DateTime> availableDates = [];

  @override
  void initState() {
    super.initState();
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorialDialog());
    }
    _fetchProfiles().then((_) {
      setState(() {
        isLoading = false;
      });
    });

    _fetchAvailableDates();
    _fetchCurrentUserMatchMode();

    _pageController.addListener(() {
      if (_pageController.page != null &&
          _pageController.page!.round() >= profiles.length - 3) {
        _fetchProfiles();
      }
    });
  }

  void _fetchCurrentUserMatchMode() async {
    final url = Uri.parse('https://settee.jp/user-profile/${widget.currentUserId}/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        isMatchMultiple = data['match_multiple'];
      });
    } else {
      debugPrint("ユーザー情報取得失敗: ${response.body}");
    }
  }

  Future<void> _showTutorialDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('チュートリアル'),
        content: const Text('これはダミーのチュートリアル表示です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          )
        ],
      ),
    );
  }

  Future<void> _fetchProfiles() async {
    if (isFetching) return;
    isFetching = true;

    final offset = profiles.length;
    final url = Uri.parse(
        'https://settee.jp/recommended-users/${widget.currentUserId}/?offset=$offset&limit=2');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<Map<String, dynamic>> newProfiles =
          List<Map<String, dynamic>>.from(json.decode(response.body));

      setState(() {
        profiles.addAll(newProfiles);
      });

      for (var profile in newProfiles) {
        _prefetchUserImages(profile['user_id']);
      }
    }

    isFetching = false;
  }

  void _prefetchUserImages(String userId) async {
    const maxIndex = 9;
    const extensions = ['jpg', 'jpeg', 'png', 'heic', 'heif'];

    userImageUrls[userId] = {};
    setState(() {});

    for (int i = 1; i <= maxIndex; i++) {
      for (var ext in extensions) {
        final url = 'https://settee.jp/images/${userId}/${userId}_${i}.${ext}';
        final response = await http.head(Uri.parse(url));
        if (response.statusCode == 200) {
          userImageUrls[userId]![i] = url;
          precacheImage(NetworkImage(url), context);
          setState(() {});
          break;
        }
      }
    }
  }

  Widget _buildProfileImage(String userId) {
    final imageUrls = userImageUrls[userId];

    // 画像ロード中（null）の場合はプログレス表示
    if (imageUrls == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // ロード完了したが画像がなかった場合
    if (imageUrls.isEmpty) {
      return const Center(child: Text('画像がありません', style: TextStyle(color: Colors.white)));
    }

    imageIndexes[userId] ??= 0;

    return GestureDetector(
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        final dx = details.localPosition.dx;
        setState(() {
          if (dx < width / 2) {
            if (imageIndexes[userId]! > 0) {
              imageIndexes[userId] = imageIndexes[userId]! - 1;
            }
          } else {
            if (imageIndexes[userId]! < imageUrls.length - 1) {
              imageIndexes[userId] = imageIndexes[userId]! + 1;
            }
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrls.values.elementAt(imageIndexes[userId]!),
            fit: BoxFit.cover,
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imageUrls.length, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == imageIndexes[userId] ? Colors.black : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendLike(String receiverId, int likeType) async {
    final url = Uri.parse('https://settee.jp/like/');
    final body = jsonEncode({
      'sender': widget.currentUserId,
      'receiver': receiverId,
      'like_type': likeType,
    });

    await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);

    if (_pageController.page != null && _pageController.page!.round() < profiles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchAvailableDates() async {
    final url = Uri.parse(
        'https://settee.jp/user-profile/${widget.currentUserId}/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        availableDates = List<String>.from(data['available_dates'])
            .map((date) => DateTime.parse(date))
            .toList();
      });
    }
  }

  Widget _buildCalendar() {
    final today = DateTime.now().toUtc().add(const Duration(hours: 9));

    final List<DateTime> weekDates = List.generate(7, (i) => today.add(Duration(days: i)))
      ..add(DateTime(9999)); // ALLボタン用

    final List<String> weekDayLabels = weekDates.map((date) {
      if (date.year == 9999) return 'ALL';
      if (date.day == today.day && date.month == today.month && date.year == today.year) {
        return '今日';
      }
      const weekDays = ['月', '火', '水', '木', '金', '土', '日'];
      return weekDays[date.weekday - 1];
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: 6, // ボタン間の隙間を明示的に調整（必要に応じて小さく）
        alignment: WrapAlignment.center,
        children: List.generate(weekDates.length, (index) {
          final date = weekDates[index];
          final bool isAllButton = (date.year == 9999);
          final bool isTodayLabel = (weekDayLabels[index] == '今日');
          final bool isSelected = isAllButton
              ? availableDates.length == 7
              : availableDates.any((d) =>
                  d.year == date.year &&
                  d.month == date.month &&
                  d.day == date.day);

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isAllButton) {
                  availableDates = List<DateTime>.generate(7, (i) => today.add(Duration(days: i)));
                } else {
                  final normalizedDate = DateTime(date.year, date.month, date.day);
                  if (isSelected) {
                    availableDates.removeWhere((d) =>
                        d.year == normalizedDate.year &&
                        d.month == normalizedDate.month &&
                        d.day == normalizedDate.day);
                  } else {
                    availableDates.add(normalizedDate);
                  }
                }
                _updateAvailableDates();
              });
            },
            child: Column(
              children: [
                Container(
                  width: 36, // 幅を調整してぎゅっと寄せる
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.5) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    weekDayLabels[index],
                    style: TextStyle(
                      fontSize: isAllButton || isTodayLabel ? 8 : 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                if (!isAllButton)
                  Container(
                    width: 36,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${date.day}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 16),
              ],
            ),
          );
        }),
      ),
    );
  }

  Future<void> _updateAvailableDates() async {
    final url = Uri.parse(
        'https://settee.jp/user-profile/${widget.currentUserId}/update-available-dates/');
    final body = jsonEncode({
      'available_dates': availableDates
          .map((d) => d.toIso8601String().split('T')[0])
          .toList(),
    });
    await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
  }

  Widget _buildTopNavigationBar(BuildContext context, String userId, bool matchMultiple, void Function(bool) onToggleMatch) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Pマーク
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.shade800,
                width: 4,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.local_parking,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),

          // エリア選択
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AreaSelectionScreen(userId: userId)),
              );
            },
            child: const Icon(Icons.pin_drop, color: Colors.white),
          ),

          // みんなで
          GestureDetector(
            onTap: () => onToggleMatch(true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.group, color: Colors.white),
                if (matchMultiple)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    height: 2,
                    width: 20,
                    color: Colors.white,
                  ),
              ],
            ),
          ),

          // ひとりで
          GestureDetector(
            onTap: () => onToggleMatch(false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, color: Colors.white),
                if (!matchMultiple)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    height: 2,
                    width: 20,
                    color: Colors.white,
                  ),
              ],
            ),
          ),

          // 設定
          const Icon(Icons.tune_rounded, color: Colors.white),
        ],
      ),
    );
  }

  void _updateMatchMultiple(String userId, bool value) async {
    final url = Uri.parse('https://settee.jp/user-profile/$userId/update-match-multiple/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'match_multiple': value}),
    );

    if (response.statusCode == 200) {
      setState(() {
        isMatchMultiple = value;
        profiles.clear();
        currentPageIndex = 0;
      });
      await _fetchProfiles();
    } else {
      debugPrint("更新失敗: ${response.body}");
    }
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
            onTap: () {},
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
          Image.asset(
            'assets/logo_text.png',
            width: 70,
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
            child: const Icon(Icons.mail_outline, color: Colors.black),
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

  // Likeボタンのウィジェット
  Widget _iconLikeButton(
    IconData icon,
    int type,
    String receiverId, {
    double size = 50,
  }) {
    bool isPressed = false;

    return StatefulBuilder(
      builder: (context, setInnerState) {
        return GestureDetector(
          onTap: () async {
            setInnerState(() => isPressed = true);
            _sendLike(receiverId, type);
            await Future.delayed(const Duration(milliseconds: 500));
            setInnerState(() => isPressed = false);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // アニメーションする円（外側エフェクト）
              AnimatedOpacity(
                opacity: isPressed ? 0.6 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: AnimatedScale(
                  scale: isPressed ? 2.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              // ボタン本体
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: size * 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Likeボタン群（絶対配置、fastfoodにバッジ付き）
  Widget _likeButtons(String userId) {
    return Stack(
      children: [
        // Super Like（星）
        Positioned(
          bottom: 195,
          right: 75,
          child: _iconLikeButton(Icons.auto_awesome, 1, userId),
        ),
        // メッセージ Like
        Positioned(
          bottom: 150,
          right: 95,
          child: _iconLikeButton(Icons.message, 3, userId),
        ),
        // ごちそう Like（バッジ付き）
        Positioned(
          bottom: 107,
          right: 70,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ごちそうLike ボタン
              _iconLikeButton(Icons.fastfood, 2, userId),

              // マスク付きバッジ
              Positioned(
                right: -36,
                bottom: -5,
                child: SizedBox(
                  width: 50,
                  height: 30,
                  child: CustomPaint(
                    painter: MaskedBadgePainter(
                      // ←この位置を「バッジ内の円の位置」に調整
                      overlapCenter: const Offset(-10, 0), // 例：右端から-10px, 上から0px
                      overlapRadius: 23, // ←ボタンサイズに応じて調整
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      alignment: Alignment.center,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'マッチ率\n',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 6,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: '×1.5',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 通常 Like（親指）
        Positioned(
          bottom: 140,
          right: 20,
          child: _iconLikeButton(Icons.thumb_up, 0, userId, size: 75),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollUpdateNotification>(
              onNotification: (notification) {
                // ここは既に ScrollUpdateNotification 型と保証されている
                if (notification.dragDetails != null &&
                    notification.metrics.axis == Axis.vertical &&
                    notification.scrollDelta! < 0 &&
                    _pageController.page != null &&
                    _pageController.page!.round() > 0) {
                  _pageController.jumpToPage(_pageController.page!.round());
                  return true;
                }
                return false;
              },
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    itemCount: profiles.length,
                    onPageChanged: (index) {
                      setState(() {
                        currentPageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onDoubleTap: () {
                              _sendLike(profile['user_id'], 0);
                              if (_pageController.page != null &&
                                  _pageController.page!.round() < profiles.length - 1) {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                            child: _buildProfileImage(profile['user_id']),
                          ),
                          SafeArea(
                            child: Column(
                              children: [
                                _buildTopNavigationBar(
                                  context,
                                  widget.currentUserId,
                                  isMatchMultiple ?? true,
                                  (bool newValue) => _updateMatchMultiple(widget.currentUserId, newValue),
                                ),
                                _buildCalendar(),
                                const Spacer(),
                              ],
                            ),
                          ),
                          _likeButtons(profile['user_id']),
                          // 戻るボタン
                          Positioned(
                            bottom: 100,
                            left: 30,
                            child: GestureDetector(
                              onTap: () {
                                if (_pageController.page != null &&
                                    _pageController.page!.round() > 0) {
                                  _pageController.previousPage(
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              },
                              child: Container(
                                width: 35,
                                height: 35,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.keyboard_arrow_up_outlined,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // ユーザー情報
                          Positioned(
                            bottom: 35,
                            left: 30,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${profile['nickname']}  ${profile['age']}',
                                  style: GoogleFonts.notoSansJp(
                                    textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 15,
                            left: 32,
                            child: Text(
                              (profile['selected_area']?.join(' / ') ?? ''),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // 左端の進捗バー
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildVerticalProgressBar(
                          currentPageIndex, profiles.length),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavigationBar(context, widget.currentUserId),
    );
  }

  /// 進捗バーウィジェット
  Widget _buildVerticalProgressBar(int currentIndex, int totalCount) {
    int topDots = 0;
    int bottomDots = 0;

    if (currentIndex == 0) {
      topDots = 0;
      bottomDots = 5;
    } else if (currentIndex == 1) {
      topDots = 1;
      bottomDots = 4;
    } else if (currentIndex == 2) {
      topDots = 2;
      bottomDots = 3;
    } else if (currentIndex >= 3 && currentIndex < totalCount - 2) {
      topDots = 3;
      bottomDots = 2;
    } else if (currentIndex == totalCount - 2) {
      topDots = 4;
      bottomDots = 1;
    } else if (currentIndex == totalCount - 1) {
      topDots = 5;
      bottomDots = 0;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey(currentIndex),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(topDots, (_) => _buildWhiteDot()),
          _buildGrayBar(),
          ...List.generate(bottomDots, (_) => _buildWhiteDot()),
        ],
      ),
    );
  }

  Widget _buildWhiteDot() {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildGrayBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      width: 8,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
    );
  }

  List<Color> _generateGradientFromColor(Color baseColor) {
    // 明るさを調整してグラデーションを作成
    final hsl = HSLColor.fromColor(baseColor);
    final lighter = hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    final darker = hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();

    return [lighter, darker];
  }

  Widget _likeButton(
    String label,
    int type,
    String receiverId,
    Color color, {
    double size = 60,
  }) {
    final bool isNormalLike = (type == 0);

    return GestureDetector(
      onTap: () => _sendLike(receiverId, type),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isNormalLike
                ? [Color.fromARGB(255, 0, 255, 238), Color.fromARGB(255, 0, 13, 255)]
                : _generateGradientFromColor(color),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label.replaceAll(" ", "\n"),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isNormalLike ? Colors.white : Colors.black,
            fontSize: isNormalLike ? (size / 4) * 1.5 : (size / 5.5),
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class MaskedBadgePainter extends CustomPainter {
  final Offset overlapCenter;
  final double overlapRadius;

  MaskedBadgePainter({required this.overlapCenter, required this.overlapRadius});

  @override
  void paint(Canvas canvas, Size size) {
    // 新しいレイヤーに描画（これが重要）
    final Paint layerPaint = Paint();
    canvas.saveLayer(Offset.zero & size, layerPaint);

    // Step 1: バッジ背景描画（白）
    final badgePaint = Paint()..color = Colors.white;
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(4),
    );
    canvas.drawRRect(badgeRRect, badgePaint);

    // Step 2: くり抜き（透明化）
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear;
    canvas.drawCircle(overlapCenter, overlapRadius, clearPaint);

    // レイヤーの描画を反映
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
