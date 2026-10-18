import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/contact_provider.dart';
import '../services/apis/group_api.dart';
import '../theme/app_theme.dart';
import '../utils/qr_payload.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/group_avatar.dart';
import '../widgets/qr_code_card.dart';

class GroupInfoPage extends StatelessWidget {
  final int groupId;
  final String groupName;
  final ValueChanged<int>? onMemberCount;
  final ValueChanged<String>? onAnnouncementChanged;
  final ValueChanged<String>? onNameChanged;
  final void Function(int userId, String name, String? avatar)? onMemberTap;

  const GroupInfoPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.onMemberCount,
    this.onAnnouncementChanged,
    this.onNameChanged,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('聊天信息')),
      body: GroupInfoDrawer(
        groupId: groupId,
        groupName: groupName,
        showClose: false,
        onClose: () => Navigator.of(context).maybePop(),
        onMemberCount: onMemberCount,
        onAnnouncementChanged: onAnnouncementChanged,
        onNameChanged: onNameChanged,
        onMemberTap: onMemberTap,
      ),
    );
  }
}

/// 群资料右侧抽屉，嵌在聊天面板里，不单独占一整页。
class GroupInfoDrawer extends StatefulWidget {
  final int groupId;
  final String groupName;
  final bool showClose;
  final VoidCallback? onClose;
  final ValueChanged<int>? onMemberCount;
  final ValueChanged<String>? onAnnouncementChanged;
  final ValueChanged<String>? onNameChanged;
  final void Function(int userId, String name, String? avatar)? onMemberTap;

  const GroupInfoDrawer({
    super.key,
    required this.groupId,
    required this.groupName,
    this.showClose = true,
    this.onClose,
    this.onMemberCount,
    this.onAnnouncementChanged,
    this.onNameChanged,
    this.onMemberTap,
  });

  @override
  State<GroupInfoDrawer> createState() => _GroupInfoDrawerState();
}

class _GroupInfoDrawerState extends State<GroupInfoDrawer> {
  final GroupApi _api = GroupApi();
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic> _group = {};
  List<_MemberView> _members = [];
  List<Map<String, dynamic>> _requests = [];
  String _remark = '';
  String _query = '';
  bool _loading = true;
  bool _busy = false;
  bool _expanded = false;
  String? _error;

  int get _myId {
    final user = context.read<AuthProvider>().user;
    return int.tryParse(user?.imUserId ?? '') ?? int.tryParse(user?.id ?? '') ?? 0;
  }

  _MemberView? get _me {
    for (final member in _members) {
      if (member.userId == _myId) return member;
    }
    return null;
  }

  int get _myRole => _me?.role ?? 0;
  bool get _isOwner => _myRole == 2;
  bool get _canManage => _myRole >= 1;

  bool get _canInvite {
    final joinType = _asInt(_group['joinType']);
    return joinType != 2 || _isOwner;
  }

  List<_MemberView> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _members;
    return _members.where((member) => member.name.toLowerCase().contains(query)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_members.isEmpty && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    Map<String, dynamic> group = _group;
    try {
      group = await _api.getGroupInfo(widget.groupId);
    } catch (_) {}

    List<Map<String, dynamic>> rawMembers = [];
    Object? memberError;
    try {
      rawMembers = await _api.fetchMembers(widget.groupId);
    } catch (e) {
      memberError = e;
    }

    if (!mounted) return;
    final contacts = context.read<ContactProvider>().contacts;
    final me = context.read<AuthProvider>().user;
    final members = rawMembers.map((row) => _MemberView.from(row, contacts, me)).toList();
    final myRole = members.where((member) => member.userId == _myId).map((member) => member.role).firstOrNull;

    List<Map<String, dynamic>> requests = [];
    if (myRole != null && myRole >= 1) {
      try {
        final raw = await _api.joinRequests(widget.groupId);
        requests = raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      } catch (_) {}
    }

    String remark = _remark;
    try {
      final prefs = await SharedPreferences.getInstance();
      remark = prefs.getString('caoim_group_remark_${widget.groupId}') ?? '';
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _group = group;
      if (memberError == null) {
        _members = members;
        _error = null;
      } else if (_members.isEmpty) {
        _error = '成员加载失败';
      }
      _requests = requests;
      _remark = remark;
      _loading = false;
    });
    if (memberError == null) {
      widget.onMemberCount?.call(members.length);
      GroupAvatarCache.instance.put(
        widget.groupId,
        members
            .map((member) => GroupAvatarSlot(name: member.name, avatar: member.avatar, order: member.order))
            .toList(),
      );
    }
    if (group.isNotEmpty) {
      final name = group['name']?.toString() ?? '';
      if (name.isNotEmpty) widget.onNameChanged?.call(name);
      widget.onAnnouncementChanged?.call(group['introduction']?.toString() ?? '');
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success);
      await _load();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _editText({
    required String title,
    required String initial,
    String hint = '',
    int maxLength = 50,
    int maxLines = 1,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _editName() async {
    final current = _group['name']?.toString() ?? widget.groupName;
    final text = await _editText(title: '群聊名称', initial: current, maxLength: 30);
    if (text == null || text.isEmpty || text == current) return;
    await _run(() => _api.updateName(widget.groupId, text));
  }

  Future<void> _editAnnouncement() async {
    final current = _group['introduction']?.toString() ?? '';
    final text = await _editText(title: '群公告', initial: current, hint: '输入群公告', maxLength: 500, maxLines: 4);
    if (text == null) return;
    await _run(() => _api.updateSettings(widget.groupId, introduction: text));
  }

  Future<void> _editRemark() async {
    final text = await _editText(title: '备注', initial: _remark, hint: '仅自己可见', maxLength: 32);
    if (text == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caoim_group_remark_${widget.groupId}', text);
    if (!mounted) return;
    setState(() => _remark = text);
  }

  Future<void> _editMyNickname() async {
    final current = _me?.groupNickname ?? '';
    final text = await _editText(title: '我在本群的昵称', initial: current, hint: '输入群昵称', maxLength: 50);
    if (text == null) return;
    await _run(() => _api.updateMyNickname(widget.groupId, text));
  }

  Future<void> _invite() async {
    final contacts = context.read<ContactProvider>().contacts;
    final memberIds = _members.map((item) => item.userId).toSet();
    final candidates = contacts.where((contact) {
      final id = int.tryParse(contact.imUserId ?? '') ?? int.tryParse(contact.id) ?? 0;
      return id > 0 && !memberIds.contains(id);
    }).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      _toast('没有可邀请的好友');
      return;
    }
    final picked = await showModalBottomSheet<UserModel>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('邀请好友')),
            for (final contact in candidates)
              ListTile(
                leading: AvatarWidget(imageUrl: contact.avatar, name: contact.displayName, size: 36),
                title: Text(contact.displayName),
                onTap: () => Navigator.pop(sheetContext, contact),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final userId = int.tryParse(picked.imUserId ?? '') ?? int.tryParse(picked.id) ?? 0;
    await _run(() async {
      final status = await _api.addMember(widget.groupId, userId);
      if (status == 'pending' && mounted) {
        _toast('已提交入群申请，等待管理员验证');
      }
    });
  }

  void _showQr() {
    final rawName = _group['name']?.toString().trim() ?? '';
    final name = rawName.isNotEmpty ? rawName : widget.groupName;
    showQrCodeDialog(
      context,
      data: QrPayload.group(widget.groupId),
      title: name.isEmpty ? '群聊' : name,
      subtitle: '扫一扫加入群聊',
    );
  }

  Future<void> _openManage() async {
    final joinType = _asInt(_group['joinType']);
    final muteAll = _asInt(_group['muteAll']) == 1;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('全员禁言'),
              subtitle: const Text('开启后只有群主和管理员可以发言'),
              value: muteAll,
              onChanged: (value) {
                Navigator.pop(sheetContext);
                _run(() => _api.updateSettings(widget.groupId, muteAll: value ? 1 : 0));
              },
            ),
            ListTile(
              title: const Text('入群验证'),
              subtitle: Text(_joinTypeLabel(joinType)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickJoinType(joinType);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickJoinType(int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var type = 0; type <= 2; type++)
              ListTile(
                title: Text(_joinTypeLabel(type)),
                trailing: current == type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, type),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await _run(() => _api.updateSettings(widget.groupId, joinType: picked));
  }

  Future<void> _memberActions(_MemberView member) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isOwner && member.role != 2)
              ListTile(
                title: Text(member.role == 1 ? '取消管理员' : '设为管理员'),
                onTap: () => Navigator.pop(sheetContext, 'role'),
              ),
            if (_isOwner || member.role == 0)
              ListTile(
                title: Text(member.muted ? '解除禁言' : '禁言'),
                onTap: () => Navigator.pop(sheetContext, 'mute'),
              ),
            ListTile(
              title: Text('移出${member.name}', style: const TextStyle(color: AppTheme.errorColor)),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == 'role') {
      await _run(() => _api.setMemberRole(widget.groupId, member.userId, member.role == 1 ? 0 : 1));
    } else if (action == 'mute') {
      await _run(() => _api.setMemberMute(widget.groupId, member.userId, !member.muted));
    } else if (action == 'remove') {
      await _run(() => _api.removeMember(widget.groupId, member.userId));
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后将不再接收这个群的消息。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _api.removeMember(widget.groupId, _myId));
    widget.onClose?.call();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final searching = _query.trim().isNotEmpty;
    final showAdd = _canInvite && !searching;
    const previewSlots = 16;
    final previewCount = showAdd ? previewSlots - 1 : previewSlots;
    final showMore = !searching && !_expanded && filtered.length > previewCount;
    final visible = showMore ? filtered.take(previewCount).toList() : filtered;
    final announcement = _group['introduction']?.toString() ?? '';
    final groupName = _group['name']?.toString().isNotEmpty == true ? _group['name'].toString() : widget.groupName;
    final myNick = _me?.groupNickname.isNotEmpty == true ? _me!.groupNickname : (_me?.accountName ?? '');

    return Material(
      color: AppTheme.surface(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppTheme.divider(context))),
        ),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.inputFill(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _query = value),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '搜索群成员',
                              hintStyle: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                              prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textSecondary(context)),
                              prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ),
                      if (widget.showClose)
                        IconButton(
                          tooltip: '关闭',
                          onPressed: widget.onClose,
                          icon: Icon(Icons.close, size: 18, color: AppTheme.textSecondary(context)),
                        ),
                    ],
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_error != null && _members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Text(_error!, style: TextStyle(color: AppTheme.textSecondary(context))),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length + (showAdd ? 1 : 0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisExtent: 78,
                      ),
                      itemBuilder: (context, index) {
                        if (showAdd && index == visible.length) {
                          return _AddMemberCell(onTap: _busy ? null : _invite);
                        }
                        return _MemberCell(
                          member: visible[index],
                          onTap: () => widget.onMemberTap?.call(
                            visible[index].userId,
                            visible[index].name,
                            visible[index].avatar,
                          ),
                          onLongPress: _canManage && visible[index].userId != _myId && visible[index].role != 2
                              ? () => _memberActions(visible[index])
                              : null,
                        );
                      },
                    ),
                  ),
                  if (showMore || (_expanded && !searching && filtered.length > previewCount))
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _expanded ? '收起' : '查看更多',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF576B95)),
                            ),
                            Icon(
                              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 16,
                              color: const Color(0xFF576B95),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                const _SectionGap(),
                if (_requests.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('入群申请（${_requests.length}）', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
                  ),
                  for (final request in _requests) _requestTile(request),
                  const _SectionGap(),
                ],
                _InfoRow(
                  label: '群聊名称',
                  value: groupName,
                  onTap: _canManage && !_busy ? _editName : null,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.divider(context)),
                _InfoRow(
                  label: '群公告',
                  value: announcement.isEmpty ? '未设置' : announcement,
                  maxLines: 3,
                  onTap: _canManage && !_busy ? _editAnnouncement : null,
                ),
                const _SectionGap(),
                _InfoRow(
                  label: '备注',
                  value: _remark.isEmpty ? '群聊的备注仅自己可见' : _remark,
                  muted: _remark.isEmpty,
                  onTap: _busy ? null : _editRemark,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.divider(context)),
                _InfoRow(
                  label: '我在本群的昵称',
                  value: myNick.isEmpty ? '未设置' : myNick,
                  muted: myNick.isEmpty,
                  onTap: _busy ? null : _editMyNickname,
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.divider(context)),
                _InfoRow(
                  label: '群二维码',
                  value: '群号 ${widget.groupId}',
                  onTap: _showQr,
                ),
                if (_canManage) ...[
                  const _SectionGap(),
                  _InfoRow(
                    label: '群管理',
                    value: '全员禁言、入群验证',
                    onTap: _busy ? null : _openManage,
                  ),
                ],
                if (!_isOwner) ...[
                  const _SectionGap(),
                  InkWell(
                    onTap: _busy ? null : _leave,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('退出群聊', style: TextStyle(fontSize: 15, color: AppTheme.errorColor)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x11000000),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _requestTile(Map<String, dynamic> request) {
    final name = request['nickname']?.toString();
    final requestId = _asInt(request['id']);
    final display = name == null || name.isEmpty ? '用户${request['userId']}' : name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(display, style: const TextStyle(fontSize: 14))),
          TextButton(
            onPressed: _busy ? null : () => _run(() => _api.reviewJoin(widget.groupId, requestId, true)),
            child: const Text('同意'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _run(() => _api.reviewJoin(widget.groupId, requestId, false)),
            child: const Text('拒绝'),
          ),
        ],
      ),
    );
  }

  String _joinTypeLabel(int type) {
    switch (type) {
      case 1:
        return '需要管理员验证';
      case 2:
        return '禁止加入';
      default:
        return '成员可直接邀请';
    }
  }
}

class _MemberView {
  final int userId;
  final int role;
  final bool muted;
  final String name;
  final String accountName;
  final String groupNickname;
  final String avatar;
  final int order;

  const _MemberView({
    required this.userId,
    required this.role,
    required this.muted,
    required this.name,
    required this.accountName,
    required this.groupNickname,
    required this.avatar,
    required this.order,
  });

  factory _MemberView.from(Map<String, dynamic> row, List<UserModel> contacts, UserModel? me) {
    final userId = _asInt(row['userId']);
    final groupNickname = row['groupNickname']?.toString() ?? '';
    final accountName = row['nickname']?.toString() ?? '';
    UserModel? contact;
    for (final item in contacts) {
      final id = int.tryParse(item.imUserId ?? '') ?? int.tryParse(item.id) ?? 0;
      if (id == userId) {
        contact = item;
        break;
      }
    }
    final self = me != null && ((int.tryParse(me.imUserId ?? '') ?? 0) == userId || (int.tryParse(me.id) ?? 0) == userId);
    final remark = contact?.remark ?? '';
    final selfUser = self ? me : null;
    String name = '';
    if (remark.isNotEmpty) {
      name = remark;
    } else if (groupNickname.isNotEmpty) {
      name = groupNickname;
    } else if (accountName.isNotEmpty) {
      name = accountName;
    } else if (contact != null && contact.displayName.isNotEmpty) {
      name = contact.displayName;
    } else if (selfUser != null && selfUser.displayName.isNotEmpty) {
      name = selfUser.displayName;
    } else {
      name = '用户$userId';
    }
    var avatar = row['avatar']?.toString() ?? '';
    if (avatar.isEmpty) avatar = contact?.avatar ?? selfUser?.avatar ?? '';
    return _MemberView(
      userId: userId,
      role: _asInt(row['role']),
      muted: row['mute'] == true || row['mute'] == 1,
      name: name,
      accountName: accountName.isNotEmpty ? accountName : (selfUser?.displayName ?? contact?.displayName ?? ''),
      groupNickname: groupNickname,
      avatar: avatar,
      order: _memberOrder(row),
    );
  }
}

class _MemberCell extends StatelessWidget {
  final _MemberView member;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MemberCell({required this.member, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            AvatarWidget(imageUrl: member.avatar, name: member.name, size: 46),
            const SizedBox(height: 4),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMemberCell extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddMemberCell({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            CustomPaint(
              painter: _DashCirclePainter(),
              child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.add, size: 22, color: AppTheme.textSecondary(context)),
              ),
            ),
            const SizedBox(height: 4),
            Text('添加', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

class _DashCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD0D0D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addOval(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2));
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + 3;
        dashed.addPath(metric.extractPath(distance, end > metric.length ? metric.length : end), Offset.zero);
        distance += 6;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final int maxLines;
  final bool muted;

  const _InfoRow({
    required this.label,
    required this.value,
    this.onTap,
    this.maxLines = 1,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.3, color: muted ? AppTheme.textSecondary(context) : AppTheme.textPrimary(context)),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary(context)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.background(context),
      child: SizedBox(height: 8, width: double.infinity),
    );
  }
}

int _memberOrder(Map<String, dynamic> row) {
  final join = row['joinTime'];
  if (join is num && join > 0) return join.toInt();
  if (join is String) {
    final parsed = DateTime.tryParse(join);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  final memberId = _asInt(row['memberId'] ?? row['id']);
  if (memberId > 0) return memberId;
  return _asInt(row['userId']);
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
