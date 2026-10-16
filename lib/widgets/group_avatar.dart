import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/apis/group_api.dart';

class GroupAvatarSlot {
  final String name;
  final String avatar;
  final int order;

  const GroupAvatarSlot({
    required this.name,
    this.avatar = '',
    this.order = 0,
  });
}

/// 群头像拼图缓存。会话列表和群资料共用，避免每个格子重复请求成员。
class GroupAvatarCache extends ChangeNotifier {
  GroupAvatarCache._();

  static final GroupAvatarCache instance = GroupAvatarCache._();

  final Map<int, List<GroupAvatarSlot>> _slots = {};
  final Map<int, Future<void>> _loading = {};

  List<GroupAvatarSlot>? peek(int groupId) => _slots[groupId];

  void put(int groupId, List<GroupAvatarSlot> slots) {
    if (groupId <= 0) return;
    final sorted = [...slots]..sort((a, b) => a.order.compareTo(b.order));
    _slots[groupId] = sorted.take(9).toList();
    notifyListeners();
  }

  Future<void> ensure(int groupId) {
    if (groupId <= 0 || _slots.containsKey(groupId)) return Future.value();
    return _loading.putIfAbsent(groupId, () async {
      try {
        final rows = await GroupApi().fetchMembers(groupId);
        put(
          groupId,
          rows.map((row) {
            final groupNick = row['groupNickname']?.toString() ?? '';
            final account = row['nickname']?.toString() ?? '';
            final userId = row['userId']?.toString() ?? '';
            return GroupAvatarSlot(
              name: groupNick.isNotEmpty ? groupNick : (account.isNotEmpty ? account : '用户$userId'),
              avatar: row['avatar']?.toString() ?? '',
              order: _orderOf(row),
            );
          }).toList(),
        );
      } catch (_) {
        if (!_slots.containsKey(groupId)) {
          _slots[groupId] = const [];
          notifyListeners();
        }
      } finally {
        _loading.remove(groupId);
      }
    });
  }
}

int _orderOf(Map<String, dynamic> row) {
  final join = row['joinTime'];
  if (join is num && join > 0) return join.toInt();
  if (join is String) {
    final parsed = DateTime.tryParse(join);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  final memberId = int.tryParse('${row['memberId'] ?? row['id'] ?? ''}') ?? 0;
  if (memberId > 0) return memberId;
  return int.tryParse('${row['userId'] ?? ''}') ?? 0;
}

/// 用最多 9 名成员的头像拼成群头像，规则与微信一致。
class GroupAvatar extends StatefulWidget {
  final int groupId;
  final double size;
  final String fallbackName;

  const GroupAvatar({
    super.key,
    required this.groupId,
    required this.size,
    this.fallbackName = '',
  });

  @override
  State<GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  @override
  void initState() {
    super.initState();
    GroupAvatarCache.instance.addListener(_onCache);
    GroupAvatarCache.instance.ensure(widget.groupId);
  }

  @override
  void didUpdateWidget(covariant GroupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      GroupAvatarCache.instance.ensure(widget.groupId);
    }
  }

  @override
  void dispose() {
    GroupAvatarCache.instance.removeListener(_onCache);
    super.dispose();
  }

  void _onCache() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final slots = GroupAvatarCache.instance.peek(widget.groupId) ?? const <GroupAvatarSlot>[];
    final radius = widget.size * 0.12;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ColoredBox(
          color: const Color(0xFFDDDEE0),
          child: slots.isEmpty
              ? _LetterTile(name: widget.fallbackName, size: widget.size)
              : _Collage(slots: slots, side: widget.size),
        ),
      ),
    );
  }
}

class _Collage extends StatelessWidget {
  final List<GroupAvatarSlot> slots;
  final double side;

  const _Collage({required this.slots, required this.side});

  @override
  Widget build(BuildContext context) {
    final rects = _slotsFor(slots.length, side);
    return Stack(
      children: [
        for (var i = 0; i < rects.length && i < slots.length; i++)
          Positioned.fromRect(
            rect: rects[i],
            child: _MemberTile(slot: slots[i]),
          ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GroupAvatarSlot slot;

  const _MemberTile({required this.slot});

  @override
  Widget build(BuildContext context) {
    if (slot.avatar.isEmpty) {
      return _LetterTile(name: slot.name, size: 40);
    }
      return CachedNetworkImage(
      imageUrl: slot.avatar,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => _LetterTile(name: slot.name, size: 0),
      placeholder: (context, url) => const ColoredBox(color: Color(0xFFE7E7E7)),
    );
  }
}

class _LetterTile extends StatelessWidget {
  final String name;
  final double size;

  const _LetterTile({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = constraints.maxWidth > 0 ? constraints.maxWidth : size;
        final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);
        final color = _palette[letter.hashCode.abs() % _palette.length];
        return ColoredBox(
          color: color,
          child: Center(
            child: Text(
              letter,
              style: TextStyle(color: Colors.white, fontSize: tile * 0.42, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );
  }
}

const _palette = [
  Color(0xFF7D91B4),
  Color(0xFF6AA8D9),
  Color(0xFF7EBF8E),
  Color(0xFFE0A15A),
  Color(0xFFD57A7A),
  Color(0xFF9A84C7),
];

/// 微信群头像格子：1 张铺满，2–4 张用两列，5–9 张用三列，缺行居中。
List<Rect> _slotsFor(int count, double side) {
  final n = count.clamp(1, 9).toInt();
  final padding = side * 0.04;
  final gap = side * 0.03;
  if (n == 1) {
    final cell = side - padding * 2;
    return [Rect.fromLTWH(padding, padding, cell, cell)];
  }

  final List<int> rows;
  final double cell;
  if (n <= 4) {
    cell = (side - padding * 2 - gap) / 2;
    if (n == 2) {
      rows = [2];
    } else if (n == 3) {
      rows = [1, 2];
    } else {
      rows = [2, 2];
    }
  } else {
    cell = (side - padding * 2 - gap * 2) / 3;
    switch (n) {
      case 5:
        rows = [2, 3];
      case 6:
        rows = [3, 3];
      case 7:
        rows = [1, 3, 3];
      case 8:
        rows = [2, 3, 3];
      default:
        rows = [3, 3, 3];
    }
  }

  final blockHeight = rows.length * cell + (rows.length - 1) * gap;
  var top = (side - blockHeight) / 2;
  final rects = <Rect>[];
  for (final columns in rows) {
    final rowWidth = columns * cell + (columns - 1) * gap;
    var left = (side - rowWidth) / 2;
    for (var i = 0; i < columns; i++) {
      rects.add(Rect.fromLTWH(left, top, cell, cell));
      left += cell + gap;
    }
    top += cell + gap;
  }
  return rects;
}
