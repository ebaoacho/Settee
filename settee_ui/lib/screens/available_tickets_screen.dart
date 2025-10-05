import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// --------------------------------------------
/// モデル
/// --------------------------------------------
class Ticket {
  final String id;
  final String title;
  final String subtitle;
  final int points;
  final String iconPath;
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
  Ticket(
    id: 'settee_plus_1day',
    title: 'Settee+1日分',
    subtitle: '※有効期限30日間',
    points: 65,
    iconPath: 'assets/settee_plus.png',
    heroTitle: 'Settee+Ticket 1日分',
    lead: 'Settee+Ticketを利用すると、\n特定の機能を解放することができます。',
    recommend: ['出会いの可能性を広げたい。', '気になってくれているユーザを知りたい。'],
    notes: [
      'このチケットはSetteeポイント65ptで交換が可能です。',
      '交換後1日間、この機能の利用が可能となります（有効期限30日）。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
  Ticket(
    id: 'settee_vip_1day',
    title: 'SetteeVIP1日分',
    subtitle: '※有効期限30日間',
    points: 65,
    iconPath: 'assets/settee_plus.png',
    heroTitle: 'SetteeVIPTicket 1日分',
    lead: 'SetteeVIPTicketを利用すると、\n特定の機能を解放することができます。',
    recommend: ['出会いの可能性を広げたい。', '気になってくれているユーザを知りたい。'],
    notes: [
      'このチケットはSetteeポイント65ptで交換が可能です。',
      '交換後1日間、この機能の利用が可能となります（有効期限30日）。',
      '交換後のキャンセル、返品、変更は行えません。',
      '反映まで少々のお時間を要する場合がございます。',
      'このチケットはマッチを保証するものではありません。',
    ],
  ),
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

class AvailableTicketsScreen extends StatefulWidget {
  final String userId;
  const AvailableTicketsScreen({super.key, required this.userId});

  @override
  State<AvailableTicketsScreen> createState() => _AvailableTicketsScreenState();
}

class _AvailableTicketsScreenState extends State<AvailableTicketsScreen> {
  bool _loading = true;
  String? _error;
  List<OwnedTicket> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http.get(Uri.parse('https://settee.jp/users/${widget.userId}/tickets/'));
      if (resp.statusCode != 200) {
        throw Exception('Failed to load tickets (${resp.statusCode})');
      }
      final List<dynamic> data = jsonDecode(resp.body);
      final items = data.map((e) => OwnedTicket.fromJson(e)).toList();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _useTicket(OwnedTicket t) async {
    try {
      final resp = await http.post(
        Uri.parse('https://settee.jp/users/${widget.userId}/tickets/${t.id}/use/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      if (resp.statusCode != 200) {
        throw Exception('Use failed (${resp.statusCode})');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('チケットを適用しました')),
      );
      await _fetchTickets();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('適用に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('利用可能なTicket', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _fetchTickets)
              : _items.isEmpty
                  ? const _EmptyView()
                  : RefreshIndicator(
                      onRefresh: _fetchTickets,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemBuilder: (_, i) => _OwnedTicketTile(
                          item: _items[i],
                          onUse: _useTicket,
                        ),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: _items.length,
                      ),
                    ),
    );
  }
}

class _OwnedTicketTile extends StatelessWidget {
  final OwnedTicket item;
  final Future<void> Function(OwnedTicket) onUse;
  const _OwnedTicketTile({required this.item, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final t = ticketFromCode(item.ticketCode);
    final isUsable = item.status == 'unused';
    final statusColor = () {
      switch (item.status) {
        case 'unused': return Colors.lightGreenAccent.shade400;
        case 'used': return Colors.grey.shade400;
        case 'expired': return Colors.orange.shade300;
        default: return Colors.white70;
      }
    }();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 左：アイコン（全面）
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56, height: 56,
              child: t == null
                  ? const ColoredBox(color: Colors.black12)
                  : Image.asset(t.iconPath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // 中央：タイトル/サブ + 期限
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t?.title ?? '不明なチケット (${item.ticketCode})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (t?.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    t!.subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusPill(text: item.status, color: statusColor),
                    const SizedBox(width: 8),
                    if (item.expiresAt != null)
                      Text(
                        '有効期限: ${_fmtDateTime(item.expiresAt!)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 右：使うボタン
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isUsable ? const Color(0xFF9D9D9D) : Colors.grey.shade700,
              disabledBackgroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            onPressed: isUsable ? () => onUse(item) : null,
            child: const Text(
              '使う',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        border: Border.all(color: color.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text('保有しているチケットはありません', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('読み込みに失敗しました\n$message', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtDateTime(DateTime dt) {
  // ローカル表示に合わせる簡易フォーマッタ
  return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
         '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class OwnedTicket {
  final int id;
  final int ticketCode;
  final String status; // 'unused' | 'used' | 'expired'
  final DateTime acquiredAt;
  final DateTime? expiresAt;

  OwnedTicket({
    required this.id,
    required this.ticketCode,
    required this.status,
    required this.acquiredAt,
    required this.expiresAt,
  });

  factory OwnedTicket.fromJson(Map<String, dynamic> j) {
    return OwnedTicket(
      id: j['id'] as int,
      ticketCode: j['ticket_code'] as int,
      status: j['status'] as String,
      acquiredAt: DateTime.parse(j['acquired_at'] as String),
      expiresAt: j['expires_at'] != null ? DateTime.parse(j['expires_at'] as String) : null,
    );
  }
}
