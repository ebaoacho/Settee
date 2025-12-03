import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// メイン画面の“見た目だけ”を完全再現するプレビュー画面。
/// - すべてのボタン/スワイプ/ダブルタップ等の機能は無効化
/// - 自分の写真/プロフィール情報を見た目だけで重ねる
class ProfilePreviewScreen extends StatefulWidget {
  final String userId;
  final String nickname;
  final String birthDateText; // 例: 1998-04-12 または '未設定'

  // 基本情報（未設定可）
  final String gender;     // '未設定' でもOK
  final String mbti;       // '未設定' でもOK
  final String drinking;   // '未設定' でもOK
  final String zodiac;     // '未設定' でもOK
  final String university; // '未設定' でもOK
  final String smoking;    // '未設定' でもOK

  // 任意で基本情報に含めたい項目（今回の要望では表示側では使わないが props として受け取っておく）
  final String occupation; // '未設定' でもOK
  final String height;     // '未設定' でもOK

  // 左カラム 2枚目系
  final String seeking;     // '未設定' でもOK
  final String preference;  // '未設定' でもOK

  // あるなら渡してください（なくても動作可）
  final List<String>? selectedAreas;   // 例: ['渋谷','新宿']
  final List<String>? availableDates;  // 例: ['2025-03-05','2025-03-07']

  const ProfilePreviewScreen({
    Key? key,
    required this.userId,
    required this.nickname,
    required this.birthDateText,
    required this.gender,
    required this.mbti,
    required this.drinking,
    required this.zodiac,
    required this.university,
    required this.smoking,
    required this.occupation,
    required this.height,
    required this.seeking,
    required this.preference,
    this.selectedAreas,
    this.availableDates,
  }) : super(key: key);

  @override
  State<ProfilePreviewScreen> createState() => _ProfilePreviewScreenState();
}

class _ProfilePreviewScreenState extends State<ProfilePreviewScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  int _slideSign = 1;

  static const double _rightPanelReservedHeight = 80.0;

  // 画像URL（最大3枚想定）を取得（存在確認）
  Future<List<String?>> _loadMyImages() async {
    final urls = <String?>[];
    for (int i = 1; i <= 3; i++) {
      urls.add(await _getExistingImageUrl(widget.userId, i, const ['jpg', 'jpeg', 'png', 'heic', 'heif']));
    }
    return urls;
  }

  Future<String?> _getExistingImageUrl(
    String userId,
    int index,
    List<String> extensions,
  ) async {
    for (final ext in extensions) {
      final url = 'https://settee.jp/images/$userId/${userId}_$index.$ext';
      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          return url;
        }
      } catch (_) {}
    }
    return null;
  }

  int? _ageFromBirth(String birthText) {
    if (birthText.isEmpty || birthText == '未設定') return null;
    try {
      final y = int.parse(birthText.substring(0, 4));
      final m = int.parse(birthText.substring(5, 7));
      final d = int.parse(birthText.substring(8, 10));
      final bd = DateTime(y, m, d);
      final now = DateTime.now();
      var age = now.year - bd.year;
      if (DateTime(now.year, now.month, now.day).isBefore(DateTime(now.year, bd.month, bd.day))) {
        age -= 1;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  // ===== 見た目を合わせるUIパーツ =====

  Widget _buildTopNavigationBarPreview() {
    // メインと同じ見た目。操作は無効化（onTapなし）
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _CircleBadge(),
          Icon(Icons.place, color: Colors.white),
          _IconWithUnderline(icon: Icons.group, underlined: true),
          _IconWithUnderline(icon: Icons.person, underlined: false),
          Icon(Icons.tune, color: Colors.white),
        ],
      ),
    );
  }

  // カレンダー：押せなくてOK・曜日ラベル/日付数字は常に白背景
  Widget _buildCalendarPreview() {
    final today = DateTime.now().toUtc().add(const Duration(hours: 9));
    final baseToday = DateTime(today.year, today.month, today.day);

    final List<DateTime> weekDates = List.generate(7, (i) => baseToday.add(Duration(days: i)))
      ..add(DateTime(9999)); // ALL

    final List<String> weekDayLabels = weekDates.map((date) {
      if (date.year == 9999) return 'ALL';
      if (date.day == baseToday.day && date.month == baseToday.month && date.year == baseToday.year) {
        return '今日';
      }
      const weekDays = ['月', '火', '水', '木', '金', '土', '日'];
      return weekDays[date.weekday - 1];
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: 6,
        alignment: WrapAlignment.center,
        children: List.generate(weekDates.length, (index) {
          final date = weekDates[index];
          final bool isAllButton = (date.year == 9999);
          final bool isTodayLabel = (weekDayLabels[index] == '今日');

          return Column(
            children: [
              // ① 曜日ラベル（常に白背景）
              Container(
                width: 36,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
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
              // ② 日付数字（ALL 以外は常に白背景）
              if (!isAllButton)
                Container(
                  width: 36,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
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
          );
        }),
      ),
    );
  }

  // === タグ（白・固定幅）
  Widget _whiteTag(String label, IconData icon, double width) {
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 10, color: Colors.black),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600, fontSize: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === タグ（灰）
  Widget _grayTag(String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF424242),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === タグ（灰・縦書きっぽく）
  Widget _grayTagVertical(String label, {IconData? icon}) {
    final String vertical =
        (label.length >= 2) ? '${label[0]}\n${label.substring(1)}' : label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF424242),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(height: 4),
          ],
          Text(
            vertical,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10, height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ── 左カラム：「基本情報」見出し＋2行3列グリッド（メインに合わせる）
  Widget _leftBasicInfoBlock() {
    final items = <_TagItem>[
      if (widget.gender.trim().isNotEmpty && widget.gender != '未設定')
        _TagItem(widget.gender, Icons.wc),
      if (widget.mbti.trim().isNotEmpty && widget.mbti != '未設定')
        _TagItem(widget.mbti, Icons.psychology_alt),
      if (widget.drinking.trim().isNotEmpty && widget.drinking != '未設定')
        _TagItem(widget.drinking, Icons.local_bar),
      if (widget.zodiac.trim().isNotEmpty && widget.zodiac != '未設定')
        _TagItem(widget.zodiac, Icons.auto_awesome),
      if (widget.university.trim().isNotEmpty && widget.university != '未設定')
        _TagItem(widget.university, Icons.school),
      if (widget.smoking.trim().isNotEmpty && widget.smoking != '未設定')
        _TagItem(widget.smoking, Icons.smoking_rooms),
    ];

    const reservedHeight = 110.0;
    if (items.isEmpty) return const SizedBox(height: reservedHeight);

    const columns = 3;
    const crossSpacing = 6.0;
    const mainSpacing  = 6.0;

    return SizedBox(
      height: reservedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth - crossSpacing * (columns - 1)) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '基本情報',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: crossSpacing,
                    mainAxisSpacing: mainSpacing,
                    // _whiteTag の高さ(32)＋ゆとりに合わせて比率調整（= 見た目重視）
                    childAspectRatio: cellWidth / 24.0,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _whiteTag(items[i].label, items[i].icon, cellWidth),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 左カラム：2行1列「求めているのは」
  Widget _leftSeekingPreferenceBlock() {
    final labels = <String>[
      if (widget.seeking.trim().isNotEmpty && widget.seeking != '未設定') widget.seeking,
      if (widget.preference.trim().isNotEmpty && widget.preference != '未設定') widget.preference,
    ];

    const reservedHeight = 110.0;
    if (labels.isEmpty) return const SizedBox(height: reservedHeight);

    const double tagVisualHeight = 24.0;
    const double lineSpacing = 8.0;

    return SizedBox(
      height: reservedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                '求めているのは',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(height: lineSpacing),
                SizedBox(
                  width: itemWidth,
                  child: AspectRatio(
                    aspectRatio: itemWidth / tagVisualHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _whiteTag(labels[i], Icons.search, itemWidth),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── 右パネル：エリア＋曜日
  Widget _rightAreaAndDaysBlock() {
    final areas = (widget.selectedAreas ?? const <String>[])
        .where((e) => e.trim().isNotEmpty && e != '未設定')
        .take(4)
        .toList();

    final dayLabels = _weekdaysFromIsoWithin7Days(widget.availableDates ?? const []);
    final isAllDays = dayLabels.length == 7;

    return SizedBox(
      height: _rightPanelReservedHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 曜日（中央寄せ）
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isAllDays)
                  _grayTag('ALL', icon: Icons.access_time)
                else if (dayLabels.isEmpty)
                  _grayTag('空きなし', icon: Icons.access_time)
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < dayLabels.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          _grayTagVertical(dayLabels[i], icon: Icons.access_time),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // エリア（右端縦並び）
          if (areas.isNotEmpty) const SizedBox(width: 2),
          if (areas.isNotEmpty)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < areas.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _grayTag(areas[i], icon: Icons.place),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // 今日(JST)〜7日後(JST)に入る日付だけを抽出して ["月曜","火曜",...] を返す
  List<String> _weekdaysFromIsoWithin7Days(List<String> isoDates) {
    final nowJst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final start = DateTime(nowJst.year, nowJst.month, nowJst.day);
    final end   = start.add(const Duration(days: 7));
    final seen = <int>{};
    for (final s in isoDates) {
      if (s.length < 10) continue;
      final y = int.tryParse(s.substring(0, 4));
      final m = int.tryParse(s.substring(5, 7));
      final d = int.tryParse(s.substring(8, 10));
      if (y == null || m == null || d == null) continue;
      final dt = DateTime.utc(y, m, d);
      if (!dt.isBefore(start) && !dt.isAfter(end)) {
        seen.add(dt.weekday); // 1..7
      }
    }
    const w = ['月','火','水','木','金','土','日'];
    return [for (var i = 1; i <= 7; i++) if (seen.contains(i)) '${w[i-1]}曜'];
  }

  // ====== ここから画面 ======
  @override
  Widget build(BuildContext context) {
    final nickname = widget.nickname.isEmpty || widget.nickname == '未設定'
        ? 'あなた'
        : widget.nickname;
    final age = _ageFromBirth(widget.birthDateText);
    final nameLine = age == null ? nickname : '$nickname  $age';

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<String?>>(
        future: _loadMyImages(),
        builder: (context, snap) {
          final allImages = snap.data ?? const [null, null, null];
          // nullでない画像のみをフィルタ
          final images = allImages.where((url) => url != null).toList();
          // 画像が1枚もない場合は最低1枚分の枠を用意
          final validImages = images.isEmpty ? [null] : images;

          return Stack(
            children: [
              // 背景：現在の画像をスライドで切り替える（横方向）
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final tween = Tween<Offset>(
                      begin: Offset(_slideSign.toDouble(), 0.0), // 1=右から入る / -1=左から入る
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic));
                    return ClipRect(
                      child: SlideTransition(position: anim.drive(tween), child: child),
                    );
                  },
                  child: SizedBox.expand(
                    key: ValueKey(_pageIndex), // ← これが変わるたびにアニメする
                    child: Builder(
                      builder: (_) {
                        final url = validImages[_pageIndex];
                        if (url == null) {
                          return const ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: Icon(Icons.image_not_supported, color: Colors.white24, size: 80),
                            ),
                          );
                        }
                        return Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // グラデーションレイヤー（上部透明→下部黒）
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.0, 0.4, 0.6, 0.8, 1.0],
                    ),
                  ),
                ),
              ),

              // 上部UI（SafeArea）
              SafeArea(
                child: Column(
                  children: [
                    _buildTopNavigationBarPreview(),
                    _buildCalendarPreview(),
                    const SizedBox(height: 8),
                    const Spacer(),
                  ],
                ),
              ),

              // Likeボタン群（見た目だけ・押せない）
              const _PreviewLikeButtons(),

              // 戻る（↑矢印）ボタン風（押せない）
              Positioned(
                bottom: 180,
                left: 30,
                child: Opacity(
                  opacity: 0.6,
                  child: Container(
                    width: 35, height: 35,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Center(
                      child: Icon(Icons.keyboard_arrow_up_outlined, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),

              // 下部の 65%（白タグ） : 35%（灰タグ）オーバーレイ
              Positioned(
                bottom: 15,
                left: 15,
                right: 15,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalW = constraints.maxWidth;
                    final leftW  = totalW * 0.65;
                    final rightW = totalW * 0.33;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 左：名前 + 基本情報/求めているのは
                        SizedBox(
                          width: leftW,
                          child: (_pageIndex <= 1)
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            nameLine,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 25,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // 3点メニューの外観（押せない）
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: Colors.white),
                                          ),
                                          child: const Icon(Icons.more_horiz, color: Colors.white, size: 18),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (_pageIndex == 0)
                                      _leftBasicInfoBlock()
                                    else
                                      _leftSeekingPreferenceBlock(),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        SizedBox(width: totalW * 0.02),
                        // 右：エリア＋曜日
                        SizedBox(
                          width: rightW,
                          child: Align(alignment: Alignment.bottomRight, child: _rightAreaAndDaysBlock()),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 左端の縦進捗バー（見た目だけ）
              Positioned(
                top: 0, bottom: 0, left: 10,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _VerticalProgressBarPreview(current: _pageIndex, total: validImages.length),
                ),
              ),
              // 透明の左右タップ領域：左=前 / 右=次（スライド方向もここで指定）
              Positioned.fill(
                child: Row(
                  children: [
                    // 左タップ：前の画像へ（新画像は左から右へ = begin: Offset(-1,0)）
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_pageIndex > 0) {
                            setState(() {
                              _slideSign = -1;     // ← 左から入る（= 画面は右へ流れる見え方）
                              _pageIndex -= 1;
                            });
                          }
                        },
                      ),
                    ),

                    const SizedBox(width: 1),

                    // 右タップ：次の画像へ（新画像は右から左へ = begin: Offset(1,0)）
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_pageIndex < validImages.length - 1) {
                            setState(() {
                              _slideSign = 1;      // ← 右から入る（= 画面は左へ流れる見え方）
                              _pageIndex += 1;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const _BackPreviewButton(),
            ],
          );
        },
      ),

      // ボトムナビ（見た目同じ・押せない）
      bottomNavigationBar: const _BottomNavPreview(),
    );
  }
}

// ====== 下請けウィジェット（プレビュー用のダミー達） ======

class _CircleBadge extends StatelessWidget {
  const _CircleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade800, width: 4),
      ),
      child: const Center(
        child: Icon(Icons.local_parking, color: Colors.white, size: 12),
      ),
    );
  }
}

class _IconWithUnderline extends StatelessWidget {
  final IconData icon;
  final bool underlined;
  const _IconWithUnderline({required this.icon, required this.underlined});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        if (underlined)
          Container(
            margin: const EdgeInsets.only(top: 2),
            height: 2, width: 20, color: Colors.white,
          ),
      ],
    );
  }
}

class _PreviewLikeButtons extends StatelessWidget {
  const _PreviewLikeButtons();

  @override
  Widget build(BuildContext context) {
    // 位置はメインと同じ・押せない
    return Stack(
      children: [
        Positioned(
          bottom: 195, right: 75,
          child: _disabledCircle(Icons.auto_awesome, 50),
        ),
        Positioned(
          bottom: 150, right: 95,
          child: _disabledCircle(Icons.message, 50),
        ),
        Positioned(
          bottom: 107, right: 70,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _disabledCircle(Icons.fastfood, 50),
              Positioned(
                right: -36, bottom: -5,
                child: Opacity(
                  opacity: 0.4,
                  child: SizedBox(
                    width: 50, height: 30,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'マッチ率\n×1.5',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            
          ),
        ),
        Positioned(
          bottom: 140, right: 20,
          child: _disabledLikeButton(75),
        ),
      ],
    );
  }

  static Widget _disabledCircle(IconData icon, double size) {
    return Stack(
      children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: size * 0.6)),
        ),
      ],
    );
  }

  static Widget _disabledLikeButton(double size) {
    return Stack(
      children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Center(
            child: Image.asset(
              'assets/LikeIcon.PNG',
              width: size * 0.8,
              height: size * 0.8,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalProgressBarPreview extends StatelessWidget {
  final int current;
  final int total;
  const _VerticalProgressBarPreview({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 4,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == current;
          return Container(
            width: 4,
            height: active ? 28 : 18,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomNavPreview extends StatelessWidget {
  const _BottomNavPreview();

  @override
  Widget build(BuildContext context) {
    // 見た目をメインと同一に
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _BottomIcon(icon: Icons.home),
          _BottomIcon(icon: Icons.search),
          _BottomLogo(),
          _BottomIcon(icon: Icons.mail_outline),
          _BottomIcon(icon: Icons.person_outline),
        ],
      ),
    );
  }
}

  class _BottomIcon extends StatelessWidget {
    final IconData icon;
    const _BottomIcon({required this.icon});

    @override
    Widget build(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: Icon(icon, color: Colors.black),
      );
    }
  }

class _BottomLogo extends StatelessWidget {
  const _BottomLogo();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10.0),
      child: Image(
        image: AssetImage('assets/logo_text.png'),
        width: 70,
      ),
    );
  }
}

class _TagItem {
  final String label;
  final IconData icon;
  const _TagItem(this.label, this.icon);
}

class _BackPreviewButton extends StatelessWidget {
  const _BackPreviewButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 96,
      left: 32,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // ← 透明部分でも確実にヒット
          onTap: () {
            // 明示的にpop（canPop確認は不要、pushで来ているため）
            Navigator.of(context).pop();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Center(
              // 「戻る」意図が分かる左向き矢印アイコン
              child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

