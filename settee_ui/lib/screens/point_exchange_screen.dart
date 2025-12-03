import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'available_tickets_screen.dart';
import 'area_selection_screen.dart';
import 'dart:ui' as ui;

/// --------------------------------------------
/// モデル
/// --------------------------------------------
class Ticket {
  final String id;
  final String title;
  final String subtitle;
  final int points;
  final String iconPath; // 画像パス

  final String heroTitle;
  final String lead;
  final List<String> recommend;
  final List<String> notes;

  const Ticket({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.iconPath,
    required this.heroTitle,
    required this.lead,
    required this.recommend,
    required this.notes,
  });
}

const _tickets = <Ticket>[
  Ticket(
    id: 'boost',
    title: 'マッチングブースト',
    subtitle: '※24時間・限定適用',
    points: 15,
    iconPath: 'assets/boost.png',
    heroTitle: 'マッチングブーストTicket',
    lead: 'マッチングブーストTicketを利用すると、\nあなたのプロフィールが24時間、より多くのユーザーに表示されます。',
    recommend: ['素早く出会いの機会を増やしたい。', 'たくさんの人に見てもらいたい。'],
    notes: [
      'このチケットはSetteeポイント15ptで交換が可能です。',
      '交換後24時間、この機能の利用が可能となります。',
      '交換後のキャンセル、返品、変更は行えません。',
      'チケット「交換」をしてから反映まで少々のお時間を要する場合がございます。',
      'このチケットを第三者に受け渡すことは出来ません。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  Ticket(
    id: 'refine',
    title: 'ユーザーを絞り込み',
    subtitle: '※年齢/好み等の絞り込み',
    points: 25,
    iconPath: 'assets/refine.png',
    heroTitle: '絞り込みTicket',
    lead: '絞り込みTicketを利用すると、\n年齢・好みなどの条件で、より狙ったユーザーに出会いやすくなります。',
    recommend: ['条件を細かく指定して探したい。', '効率よく相手を見つけたい。'],
    notes: [
      'このチケットはSetteeポイント25ptで交換が可能です。',
      '交換後、この機能の利用が可能となります。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  Ticket(
    id: 'private',
    title: 'プライベートモード',
    subtitle: '※身バレをしたくない方へ',
    points: 35,
    iconPath: 'assets/private.png',
    heroTitle: 'プライベートモードTicket',
    lead: 'プライベートモードTicketを利用すると、\nあなたがライクを送信したユーザーにのみ、あなたのプロフィールが表示されるようになります。',
    recommend: ['身バレをしたくない。', '自分が興味があるユーザーにだけ知ってもらいたい。'],
    notes: [
      'このチケットはSetteeポイント35ptで交換が可能です。',
      '交換後365日間、この機能の利用が可能となります。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットを第三者に受け渡すことは出来ません。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  Ticket(
    id: 'message_like5',
    title: 'メッセージライク5回分',
    subtitle: '※有効期限30日間',
    points: 45,
    iconPath: 'assets/message_like.png',
    heroTitle: 'メッセージライクTicket 5回分',
    lead: 'メッセージライクTicketを利用すると、\nマッチする前にメッセージを送信することができます。',
    recommend: ['マッチする前に想いを伝えたい。', '気になるユーザーに自分をアピールしたい。'],
    notes: [
      'このチケットはSetteeポイント45ptで交換が可能です。',
      '交換後5回分、この機能の利用が可能となります（有効期限30日）。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  Ticket(
    id: 'super_like5',
    title: 'スーパーライク5回分',
    subtitle: '※有効期限30日間',
    points: 55,
    iconPath: 'assets/super_like.png',
    heroTitle: 'スーパーライクTicket 5回分',
    lead: 'スーパーライクTicketを利用すると、\n気になるユーザーに特別なライクを送信することができます。',
    recommend: ['特別な想いを伝えたい。', '気になるユーザーに自分を知ってもらいたい。'],
    notes: [
      'このチケットはSetteeポイント55ptで交換が可能です。',
      '交換後5回分、この機能の利用が可能となります（有効期限30日）。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  // Ticket(
  //   id: 'settee_plus_1day',
  //   title: 'Settee+1日分',
  //   subtitle: '※24時間・限定適用',
  //   points: 65,
  //   iconPath: 'assets/settee_plus.png',
  //   heroTitle: 'Settee+Ticket 1日分',
  //   lead: 'Settee+Ticketを利用すると、\n特定の機能を解放することができます。',
  //   recommend: ['出会いの可能性を広げたい。', '気になってくれているユーザを知りたい。'],
  //   notes: [
  //     'このチケットはSetteeポイント65ptで交換が可能です。',
  //     '交換後1日間、この機能の利用が可能となります（有効期限30日）。',
  //     '交換後のキャンセル、返品、変更は行えません。',
  //     '反映まで少々のお時間を要する場合がございます。',
  //     'このチケットはマッチを保証するものではありません。',
  //   ],
  // ),
  // Ticket(
  //   id: 'settee_vip_1day',
  //   title: 'SetteeVIP1日分',
  //   subtitle: '※有効期限30日間',
  //   points: 65,
  //   iconPath: 'assets/settee_plus.png',
  //   heroTitle: 'SetteeVIPTicket 1日分',
  //   lead: 'SetteeVIPTicketを利用すると、\n特定の機能を解放することができます。',
  //   recommend: ['出会いの可能性を広げたい。', '気になってくれているユーザを知りたい。'],
  //   notes: [
  //     'このチケットはSetteeポイント65ptで交換が可能です。',
  //     '交換後1日間、この機能の利用が可能となります（有効期限30日）。',
  //     '交換後のキャンセル、返品、変更は行えません。',
  //     '反映まで少々のお時間を要する場合がございます。',
  //     'このチケットはマッチを保証するものではありません。',
  //   ],
  // ),
];

/// ============================================
/// チケット辞書（サーバの番号 ↔ フロントのID）
/// ============================================

// サーバに渡す ticket_code -> 画面用ID
const Map<int, String> kTicketCodeToId = {
  1: 'boost',
  2: 'refine',
  3: 'private',
  4: 'message_like5',
  5: 'super_like5',
  6: 'settee_plus_1day',
  7: 'settee_vip_1day',
};

/// 逆引き：画面用IDから ticket_code を取得（API呼び出し時に使用）
int? codeFromTicketId(String id) {
  for (final e in kTicketCodeToId.entries) {
    if (e.value == id) return e.key;
  }
  return null;
}

/// APIレスポンスの ticket_code から Ticket モデルを取得（保有チケット表示で使用）
Ticket? ticketFromCode(int code) {
  final id = kTicketCodeToId[code];
  if (id == null) return null;
  try {
    return _tickets.firstWhere((t) => t.id == id);
  } catch (_) {
    return null;
  }
}

/// --------------------------------------------
/// 一覧画面（添付UIの「Settee Point交換」）
/// --------------------------------------------
class PointExchangeScreen extends StatefulWidget {
  final String userId;
  const PointExchangeScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<PointExchangeScreen> createState() => _PointExchangeScreenState();
}

class _PointExchangeScreenState extends State<PointExchangeScreen> {
  int _points = 0;

  @override
  void initState() {
    super.initState();
    _loadPoints(widget.userId);
  }

  Future<void> _loadPoints(String userId) async {
    final uri = Uri.parse('https://settee.jp/users/$userId/entitlements/');
    try {
      final resp = await http.get(
        uri,
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        if (!mounted) return;
        // 失敗時は現状維持（必要ならSnackBar）
        // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ポイント取得に失敗しました (${resp.statusCode})')));
        return;
      }

      final Map<String, dynamic> j = jsonDecode(resp.body);
      final dynamic p = j['settee_points'];

      final int newPoints = switch (p) {
        int v => v,
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      };

      if (!mounted) return;
      setState(() => _points = newPoints);
    } catch (e) {
      if (!mounted) return;
      // 必要ならユーザー通知
      // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('通信エラー: $e')));
    }
  }

  void _consumePoints(int cost) {
    setState(() => _points -= cost);
  }

  Route<T> _slideRoute<T>(Widget page, {AxisDirection direction = AxisDirection.left}) {
    Offset begin;
    switch (direction) {
      case AxisDirection.left:  begin = const Offset(1.0, 0.0);  break; // 右から入る
      case AxisDirection.right: begin = const Offset(-1.0, 0.0); break; // 左から入る
      case AxisDirection.up:    begin = const Offset(0.0, 1.0);  break;
      case AxisDirection.down:  begin = const Offset(0.0, -1.0); break;
    }
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) {
        final tween = Tween(begin: begin, end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: anim.drive(tween), child: child);
      },
    );
  }

  void _showSetteePointInfoDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Stack(
                children: [
                  _GlassCard(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Setteeポイントとは',
                                  style: TextStyle(
                                    color: Colors.white, fontSize: 20,
                                    fontWeight: FontWeight.w900, letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Setteeポイントは、ログインやマッチングで貯まり、機能解放・チケット交換に充当できます。',
                            style: TextStyle(color: Colors.white, height: 1.6, fontSize: 14),
                          ),
                          const SizedBox(height: 18),
                          const _SectionHeader(icon: Icons.card_giftcard, label: 'ポイントはどうやって手に入れるのか'),
                          const SizedBox(height: 10),
                          const _RichBullet(bold: 'ログインボーナス：', tail: '1日1ポイント'),
                          const _RichBullet(bold: '連続ログインボーナス：', tail: '7日間連続ログインで5ポイント配布（連続されなかった時点でリセット）'),
                          const _NoteBullet('※ 連続ログインボーナスは月MAX 50ポイント'),
                          const SizedBox(height: 10),
                          const _RichBullet(bold: 'マッチングしたら：', tail: '1件につき3ポイント'),
                          const _NoteBullet('※ 月10回マッチングで合計30ポイント'),
                          const SizedBox(height: 14),
                          const Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _TinyChip('1pt/日'),
                              _TinyChip('+5pt/7日'),
                              _TinyChip('MAX 50/月'),
                              _TinyChip('3pt/日上限'),
                              _TinyChip('+30pt/月'),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const _DividerFancy(),
                          const SizedBox(height: 8),
                          const _SectionHeader(icon: Icons.auto_awesome, label: '使い道'),
                          const SizedBox(height: 10),
                          const _IconLine(icon: Icons.bolt_rounded, text: '機能解放（ブースト／絞り込み／プライベートモード 等）'),
                          const _IconLine(icon: Icons.local_activity_rounded, text: '各種チケットへの交換'),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF9D9D9D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                'OK',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Positioned(
                    right: 8, top: 8,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(ctx),
                        child: Ink(
                          width: 36, height: 36,
                          decoration: ShapeDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: CircleBorder(
                              side: BorderSide(color: Colors.white.withOpacity(0.15)),
                            ),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 背景グラデーション
    final bg = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFEEEEEE), Color(0xFF0F0F0F)],
      stops: [0.0, 0.55],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          // 右→左（左へフリック）でエリア選択へ遷移
          const threshold = 150.0; // 誤作動防止の速度しきい値（必要に応じ調整）
          final v = details.primaryVelocity ?? 0.0;
          if (v < -threshold) {
            Navigator.of(context).push(
              _slideRoute(
                AreaSelectionScreen(userId: widget.userId),
                direction: AxisDirection.left, // 右からスライドイン
              ),
            );
          }
        },
        child: SafeArea(
          child: Container(
            decoration: BoxDecoration(gradient: bg),
            child: Column(
              children: [
                // --- ヘッダ ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: Row(
                    children: [
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.chevron_left, size: 28),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Settee Point交換',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),

                // --- 保有ポイント ---
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 4, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '保有 Point',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_points p',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // ← ここを縦並びの Column に
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end, // 右端に揃える
                        children: [
                          _CapsuleButton(
                            label: '利用可能なTicket',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AvailableTicketsScreen(userId: widget.userId),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _CapsuleButton(
                            label: 'Settee Pointとは',
                            onTap: _showSetteePointInfoDialog,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // --- チケット一覧 ---
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemBuilder: (context, index) {
                        final t = _tickets[index];
                        final canExchange = _points >= t.points;

                        return _TicketTile(
                          ticket: t,
                          canExchange: canExchange,
                          onTapExchange: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TicketDetailScreen(
                                  ticket: t,
                                  userId: widget.userId,
                                  currentPoints: _points,
                                ),
                              ),
                            );

                            if (!mounted) return;

                            // Map返却（サーバ残高）・bool返却（クライアント減算）どちらも対応
                            if (result is Map && result['exchanged'] == true) {
                              final int? serverPoints =
                                  result['points'] is int ? result['points'] as int : null;
                              if (serverPoints != null) {
                                setState(() => _points = serverPoints);
                              } else {
                                _consumePoints(t.points);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${t.title} を交換しました')),
                              );
                            } else if (result == true) {
                              _consumePoints(t.points);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${t.title} を交換しました')),
                              );
                            }
                          },
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemCount: _tickets.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// 詳細画面（添付UIの「Setteポイント詳細」）
/// --------------------------------------------
class TicketDetailScreen extends StatelessWidget {
  final Ticket ticket;
  final String userId;
  final int currentPoints;

  const TicketDetailScreen({
    Key? key,
    required this.ticket,
    required this.userId,
    required this.currentPoints,
  }) : super(key: key);

  // チケットID→番号の逆引きヘルパ（kTicketCodeToIdを利用）
  int? _codeFromTicketId(String id) {
    try {
      return kTicketCodeToId.entries
          .firstWhere((e) => e.value == id)
          .key;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _exchange(BuildContext context) async {
    final code = _codeFromTicketId(ticket.id);
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('不明なチケットIDです (${ticket.id})')),
      );
      return false;
    }

    // ローディング表示
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resp = await http.post(
        Uri.parse('https://settee.jp/users/$userId/tickets/exchange/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ticket_code': code}),
      );

      Navigator.of(context).pop(); // ローディング閉じる

      if (resp.statusCode == 200) {
        // サーバ側の points_balance を使って親で反映したい場合は
        // final json = jsonDecode(resp.body);
        // final newBalance = json['points_balance'] as int;
        // → Navigator.pop(context, {'exchanged': true, 'points': newBalance});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ticket.title} を交換しました')),
        );
        return true;
      } else {
        String msg = '交換に失敗しました（${resp.statusCode}）';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['detail'] != null) msg = j['detail'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return false;
      }
    } catch (e) {
      Navigator.of(context).pop(); // 念のため
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信エラー: $e')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canExchange = currentPoints >= ticket.points;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Stack(
          children: [
            // 背景グラデーション
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEEEEEE), Color(0xFF0F0F0F)],
                  stops: [0.0, 0.30],
                ),
              ),
            ),
            // コンテンツ（あなたの既存のまま）
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: Row(
                    children: [
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.chevron_left, size: 28),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Setteポイント詳細',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    child: _DetailCard(ticket: ticket),
                  ),
                ),
              ],
            ),

            // 下部の大ボタン（ここだけ差し替え）
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor:
                      canExchange ? const Color(0xFF9D9D9D) : Colors.grey.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: canExchange
                    ? () async {
                        final ok = await _exchange(context);
                        if (!context.mounted) return;
                        if (ok) {
                          // 親（PointExchangeScreen）は bool を受け取る想定でそのまま
                          Navigator.pop(context, true);
                        }
                      }
                    : null,
                child: const Text(
                  '交換する',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// パーツ群
/// --------------------------------------------

class _TicketTile extends StatelessWidget {
  final Ticket ticket;
  final bool canExchange;
  final VoidCallback onTapExchange;

  const _TicketTile({
    Key? key,
    required this.ticket,
    required this.canExchange,
    required this.onTapExchange,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardColor = const Color(0xFF141414);
    final shadow = [
      BoxShadow(
        color: Colors.black.withOpacity(0.35),
        blurRadius: 12,
        offset: const Offset(0, 8),
      )
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: shadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // アイコン：背景なし・全面表示（角丸）
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Image.asset(
                ticket.iconPath,
                fit: BoxFit.cover, // ← ここで領域いっぱいに
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 中央：テキスト
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ticket.subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          // 右：ポイント＆交換ボタン
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${ticket.points} point',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      canExchange ? const Color(0xFF9D9D9D) : Colors.grey.shade700,
                  disabledBackgroundColor: Colors.grey.shade700,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: canExchange ? onTapExchange : null,
                child: const Text(
                  '交換する',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final Ticket ticket;
  const _DetailCard({Key? key, required this.ticket}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardColor = const Color(0xFF141414);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上部：アイコン + タイトル + pt
          Row(
            children: [
              // アイコン：背景なし・全面表示（角丸）
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.asset(
                    ticket.iconPath,
                    fit: BoxFit.cover, // ← 領域いっぱい
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ticket.heroTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${ticket.points} point',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // リード
          Text(
            ticket.lead,
            style: const TextStyle(
              color: Colors.white,
              height: 1.6,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),

          // おすすめ
          const _SectionTitle('💡こんな人におすすめ！'),
          const SizedBox(height: 8),
          ...ticket.recommend.map(
            (e) => _Bullet(text: e),
          ),
          const SizedBox(height: 24),

          // 注意事項
          const _SectionTitle('📍利用条件/注意事項'),
          const SizedBox(height: 8),
          ...ticket.notes.map(
            (e) => _Bullet(text: e),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '・',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _CapsuleButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 24, offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _RichBullet extends StatelessWidget {
  final String bold;
  final String tail;
  const _RichBullet({required this.bold, required this.tail});
  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Colors.white, height: 1.6, fontSize: 14);
    const strong = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, height: 1.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white54, height: 1.6)),
          const SizedBox(width: 2),
          Expanded(
            child: RichText(
              text: TextSpan(style: body, children: [
                TextSpan(text: bold, style: strong),
                TextSpan(text: tail),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteBullet extends StatelessWidget {
  final String text;
  const _NoteBullet(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 4),
      child: Text(text, style: const TextStyle(color: Colors.white54, height: 1.5, fontSize: 12)),
    );
  }
}

class _TinyChip extends StatelessWidget {
  final String text;
  const _TinyChip(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _DividerFancy extends StatelessWidget {
  const _DividerFancy();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.25),
            Colors.white.withOpacity(0.0),
          ],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
      ),
    );
  }
}
