import 'package:flutter/material.dart';

/// フィルタ結果データ（そのまま）
class SearchFilters {
  final String? gender;          // '男性' / '女性' / null(未設定)
  final int? ageMin;             // null の場合は下限なし
  final int? ageMax;             // null の場合は上限なし
  final String? occupation;      // 完全一致 / null
  final int? heightMin;          // cm, null 可
  final int? heightMax;          // cm, null 可
  final Set<String>? mbtis;      // 複数選択 / null または空集合で未設定扱い
  final bool? includeNullMbti;

  const SearchFilters({
    this.gender,
    this.ageMin,
    this.ageMax,
    this.occupation,
    this.heightMin,
    this.heightMax,
    this.mbtis,
    this.includeNullMbti,
  });

  SearchFilters copyWith({
    String? gender,
    int? ageMin,
    int? ageMax,
    String? occupation,
    int? heightMin,
    int? heightMax,
    Set<String>? mbtis,
    bool? includeNullMbti,
  }) {
    return SearchFilters(
      gender: gender ?? this.gender,
      ageMin: ageMin ?? this.ageMin,
      ageMax: ageMax ?? this.ageMax,
      occupation: occupation ?? this.occupation,
      heightMin: heightMin ?? this.heightMin,
      heightMax: heightMax ?? this.heightMax,
      mbtis: mbtis ?? this.mbtis,
      includeNullMbti: includeNullMbti ?? this.includeNullMbti,
    );
  }
}

class SearchFilterScreen extends StatefulWidget {
  const SearchFilterScreen({
    super.key,
    this.initial,
    this.currentUserGender, // '男性' or '女性'（UI初期表示にだけ使う）
  });

  final SearchFilters? initial;
  final String? currentUserGender;

  @override
  State<SearchFilterScreen> createState() => _SearchFilterScreenState();
}

class _SearchFilterScreenState extends State<SearchFilterScreen> {
  String? _gender; // デフォルトは「異性」（currentUserGender があれば）
  String? _occupation;

  // 範囲スライダ
  RangeValues _ageRange    = const RangeValues(18, 22);
  RangeValues _heightRange = const RangeValues(160, 175);

  // 身長ON/OFF
  bool _heightEnabled = false;

  // MBTI 複数
  final Set<String> _selectedMbti = <String>{};
  bool _includeNullMbti = true; // 未設定も含める（デフォルトONにしています）

  // マスタ
  final List<String> _genderOptions = ['未設定', '男性', '女性'];
  final List<String> _occupationOptions = [
    '未設定', '大学生', '専門学生', '会社員', '経営者', '公務員', 'フリーランス', 'アルバイト', 'その他',
  ];
  final List<String> _mbtiOptions = const [
    'INTJ','INTP','ENTJ','ENTP','INFJ','INFP','ENFJ','ENFP',
    'ISTJ','ISFJ','ESTJ','ESFJ','ISTP','ISFP','ESTP','ESFP'
  ];

  // 範囲定義
  static const int kAgeMin    = 18;
  static const int kAgeMax    = 22;
  static const int kHeightMin = 120;
  static const int kHeightMax = 200;

  @override
  void initState() {
    super.initState();

    // 初期化
    final i = widget.initial;
    if (i != null) {
      _gender     = i.gender ?? widget.currentUserGender;
      _occupation = i.occupation;

      _ageRange = RangeValues(
        (i.ageMin ?? _ageRange.start.toInt()).toDouble().clamp(kAgeMin.toDouble(), kAgeMax.toDouble()),
        (i.ageMax ?? _ageRange.end.toInt()).toDouble().clamp(kAgeMin.toDouble(), kAgeMax.toDouble()),
      );

      // 身長：min/max のいずれかがある → ON
      _heightEnabled = (i.heightMin != null || i.heightMax != null);
      _heightRange = RangeValues(
        (i.heightMin ?? _heightRange.start.toInt()).toDouble().clamp(kHeightMin.toDouble(), kHeightMax.toDouble()),
        (i.heightMax ?? _heightRange.end.toInt()).toDouble().clamp(kHeightMin.toDouble(), kHeightMax.toDouble()),
      );

      // MBTI 複数
      if (i.mbtis != null) {
        _selectedMbti
          ..clear()
          ..addAll(i.mbtis!
              .map((e) => e.toUpperCase())
              .where(_mbtiOptions.contains));
      }

      _includeNullMbti = i.includeNullMbti ?? true;
    } else {
      _gender = widget.currentUserGender;
    }
  }

  // ====== 適用して閉じる ======
  void _applyAndPop() {
    final filters = SearchFilters(
      gender: _gender,
      ageMin: _ageRange.start.round(),
      ageMax: _ageRange.end.round(),
      occupation: _occupation,
      // 身長OFFなら null を返却（→ クエリに載らない）
      heightMin: _heightEnabled ? _heightRange.start.round() : null,
      heightMax: _heightEnabled ? _heightRange.end.round() : null,
      mbtis: _selectedMbti.isEmpty ? null : Set.of(_selectedMbti),
      includeNullMbti: _selectedMbti.isEmpty ? null : _includeNullMbti,
    );
    Navigator.pop(context, filters);
  }

  @override
  Widget build(BuildContext context) {
    final border  = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final divider = const Divider(height: 1, color: Colors.white24);

    return WillPopScope(
      onWillPop: () async {
        _applyAndPop(); // 端末戻るでも適用
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // ====== ヘッダー（戻る→適用） ======
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _applyAndPop,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const Text(
                      '検索条件の絞り込み',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              // ====== 本体 ======
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    // 性別
                    _Label('友だちになりたいお相手は？'),
                    _PickerField(
                      valueText: _gender ?? '未設定',
                      onTap: () => _showOptionsSheet(
                        title: '性別を選択',
                        options: _genderOptions,
                        current: _gender ?? '未設定',
                        onSelected: (v) => setState(() => _gender = v == '未設定' ? null : v),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 年齢（範囲）
                    _Label('お相手の年齢は？'),
                    const SizedBox(height: 6),
                    _buildRange(
                      context: context,
                      values: _ageRange,
                      min: kAgeMin.toDouble(),
                      max: kAgeMax.toDouble(),
                      unit: '歳',
                      onChanged: (v) => setState(() => _ageRange = v),
                    ),
                    divider,
                    const SizedBox(height: 6),

                    // 職業
                    _Label('お相手の職業は？'),
                    _PickerField(
                      valueText: _occupation ?? '未設定',
                      onTap: () => _showOptionsSheet(
                        title: '職業を選択',
                        options: _occupationOptions,
                        current: _occupation ?? '未設定',
                        onSelected: (v) => setState(() => _occupation = v == '未設定' ? null : v),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ====== 身長トグル + 範囲 ======
                    _Label('お相手の身長は？'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _heightEnabled,
                      onChanged: (v) => setState(() => _heightEnabled = v),
                      title: const Text('身長で絞り込む', style: TextStyle(color: Colors.white)),
                      activeColor: Colors.white,
                    ),
                    AbsorbPointer(
                      absorbing: !_heightEnabled, // OFF中は操作不可
                      child: Opacity(
                        opacity: _heightEnabled ? 1.0 : 0.4, // 視覚的にも無効化
                        child: _buildRange(
                          context: context,
                          values: _heightRange,
                          min: kHeightMin.toDouble(),
                          max: kHeightMax.toDouble(),
                          unit: 'cm',
                          onChanged: (v) => setState(() => _heightRange = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ====== MBTI 複数選択 ======
                    _Label('お相手のMBTIは？（複数選択可）'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _mbtiOptions.map((code) {
                        final sel = _selectedMbti.contains(code);
                        return FilterChip(
                          selected: sel,
                          showCheckmark: false,
                          label: Text(
                            code,
                            style: TextStyle(
                              color: sel ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          selectedColor: Colors.white,
                          backgroundColor: const Color(0xFF1E1E1E),
                          side: const BorderSide(color: Colors.white24),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _selectedMbti.add(code);
                            } else {
                              _selectedMbti.remove(code);
                            }
                          }),
                        );
                      }).toList(),
                    ),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('MBTI未設定のユーザーも含める', style: TextStyle(color: Colors.white)),
                      value: _includeNullMbti,
                      onChanged: _selectedMbti.isEmpty
                          ? null
                          : (v) => setState(() => _includeNullMbti = v),
                      activeColor: Colors.white,
                    ),
                  ],
                ),
              ),

              // ====== 下部「更新」 → 適用して閉じる ======
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ElevatedButton(
                    onPressed: _applyAndPop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: border,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== 共通: 範囲スライダ表示 ======
  Widget _buildRange({
    required BuildContext context,
    required RangeValues values,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 目盛り表示（任意）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${values.start.round()}$unit', style: const TextStyle(color: Colors.white70)),
              Text('${values.end.round()}$unit',   style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            trackHeight: 3,
          ),
          child: RangeSlider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            values: values,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ====== 既存のボトムシート選択 ======
  Future<void> _showOptionsSheet({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('閉じる', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (_, i) {
                    final v = options[i];
                    final selected = v == current;
                    return ListTile(
                      title: Text(v, style: const TextStyle(color: Colors.white)),
                      trailing: selected ? const Icon(Icons.check, color: Colors.redAccent) : null,
                      onTap: () {
                        onSelected(v);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 既存の補助ウィジェット（そのまま使う）
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text,
        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
  );
}

class _PickerField extends StatelessWidget {
  final String valueText;
  final VoidCallback onTap;
  const _PickerField({required this.valueText, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valueText,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
