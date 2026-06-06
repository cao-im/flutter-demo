import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../providers/contact_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/layout_provider.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';

class DesktopContactsPanel extends StatefulWidget {
  const DesktopContactsPanel({super.key});

  @override
  State<DesktopContactsPanel> createState() => _DesktopContactsPanelState();
}

class _DesktopContactsPanelState extends State<DesktopContactsPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  int? _currentUserId;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  // 新的朋友折叠展开状态
  bool _isNewFriendsExpanded = false;
  final GlobalKey _addButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ContactProvider>(context, listen: false).startListening();
      Provider.of<ContactProvider>(context, listen: false).loadContacts();
      Provider.of<ContactProvider>(context, listen: false).loadFriendRequests();
      _loadCurrentUserId();
    });
    _searchController.addListener(() => setState(() => _searchText = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final storage = await SharedPreferences.getInstance();
      final userIdStr = storage.getString('im_user_id');
      if (userIdStr != null) setState(() => _currentUserId = int.tryParse(userIdStr));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceColor,
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildContactsContent()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索联系人',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: Colors.grey[500]),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchText = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // + 号按钮，点击弹出菜单（仿微信）
          Material(
            key: _addButtonKey,
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            elevation: 0,
            child: InkWell(
              onTap: () => _showAddMenu(context),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Icon(Icons.add, size: 20, color: AppTheme.primaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示+号菜单（定位在按钮下方）
  void _showAddMenu(BuildContext context) {
    final RenderBox? button = _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height + 4,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'add_friend',
          height: 44,
          child: Row(children: [
            Icon(Icons.person_add_outlined, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('添加好友', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'group_chat',
          height: 44,
          child: Row(children: [
            Icon(Icons.group_add_outlined, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('发起群聊', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'add_friend') {
        _showAddFriendDialog(context);
      } else if (value == 'group_chat') {
        _showSuccessSnackBar('发起群聊功能开发中');
      }
    });
  }

  /// 添加好友弹窗
  void _showAddFriendDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _AddFriendDialog(),
    );
  }

  Widget _buildContactsContent() {
    return Consumer<ContactProvider>(
      builder: (context, contactProvider, _) {
        final groupedContacts = contactProvider.groupedContacts;
        final allContacts = contactProvider.contacts;

        return Row(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // 新的朋友：可折叠展开（仿微信）
                  _buildNewFriendsExpandableSection(contactProvider),

                  // 其他功能入口
                  _buildExpandableSection(icon: Icons.group_outlined, title: '群聊', count: null, isExpanded: false, onTap: () {}),
                  _buildExpandableSection(icon: Icons.article_outlined, title: '公众号', count: null, isExpanded: false, onTap: () {}),
                  _buildExpandableSection(icon: Icons.support_agent_outlined, title: '服务号', count: null, isExpanded: false, onTap: () {}),
                  Divider(height: 1, indent: 56, color: Colors.grey[200]),

                  // 联系人列表或空状态提示
                  if (allContacts.isEmpty && !contactProvider.isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('暂无联系人', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                            const SizedBox(height: 8),
                            Text('添加好友开始聊天吧', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => _showAddFriendDialog(context),
                              icon: const Icon(Icons.person_add, size: 20),
                              label: const Text('搜索并添加好友'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                elevation: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._buildContactList(contactProvider),
                ],
              ),
            ),
            if (_searchText.isEmpty && groupedContacts.isNotEmpty)
              _buildAlphabetIndex(groupedContacts.keys.toList()),
          ],
        );
      },
    );
  }

  /// 新的朋友：折叠展开区域（仿微信）
  Widget _buildNewFriendsExpandableSection(ContactProvider contactProvider) {
    final unreadCount = contactProvider.unreadFriendRequestCount;
    final requests = contactProvider.friendRequests;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题行：点击展开/收起
        InkWell(
          onTap: () {
            setState(() => _isNewFriendsExpanded = !_isNewFriendsExpanded);
            if (_isNewFriendsExpanded) {
              contactProvider.markFriendRequestsAsRead();
            }
          },
          hoverColor: AppTheme.primaryColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.person_add_outlined, size: 22, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '新的朋友',
                    style: const TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor, fontWeight: FontWeight.w500),
                  ),
                ),
                if (unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.errorColor, borderRadius: BorderRadius.circular(10)),
                    child: Text('$unreadCount', style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                AnimatedRotation(
                  turns: _isNewFriendsExpanded ? 0.5 : 0.0,
                  duration: Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),

        // 展开内容：好友请求列表（内联显示）
        if (_isNewFriendsExpanded) ...[
          Container(
            constraints: BoxConstraints(maxHeight: 280),
            child: requests.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('暂无好友请求', style: TextStyle(color: Colors.grey[400], fontSize: 13))),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: requests.length > 5 ? 5 : requests.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: Colors.grey.shade100),
                    itemBuilder: (ctx, i) => _buildCompactRequestItem(requests[i]),
                  ),
          ),
          if (requests.length > 5)
            InkWell(
              onTap: () => Navigator.of(context).pushNamed(AppRouter.newFriends),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '查看全部 ${requests.length} 条好友请求',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.primaryColor),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 紧凑版好友请求条目（用于内联展开列表）
  Widget _buildCompactRequestItem(Map<String, dynamic> request) {
    final type = _getRequestType(request);
    final fromUsername = request['fromUsername']?.toString() ?? '未知用户';
    final fromNickname = request['fromNickname']?.toString() ?? '';
    final displayName = fromNickname.isNotEmpty ? fromNickname : fromUsername;
    final avatar = type == 'received' ? request['fromAvatar'] : request['toAvatar'];
    final fromUserId = request['fromUserId'];

    final isPendingReceived = type == 'received';
    final isPendingSent = type == 'sent';
    final isAccepted = type == 'accepted';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AvatarWidget(imageUrl: avatar, name: displayName, size: 42),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: 2),
                Text(
                  isPendingReceived ? '$fromUsername 请求添加你为好友'
                  : isPendingSent ? '已向 $fromUsername 发送请求'
                  : '$fromUsername 已成为好友',
                  style: TextStyle(fontSize: 12, color: isPendingReceived ? AppTheme.primaryColor : Colors.grey),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isPendingReceived) ...[
            InkWell(onTap: () => _rejectRequest(fromUserId), child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.errorColor.withOpacity(0.5))), child: Text('拒绝', style: TextStyle(fontSize: 11, color: AppTheme.errorColor)))),
            SizedBox(width: 6),
            InkWell(onTap: () => _acceptRequest(fromUserId), child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppTheme.primaryColor), child: Text('接受', style: TextStyle(fontSize: 11, color: Colors.white)))),
          ] else if (isPendingSent)
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.access_time, size: 12, color: Colors.orange), SizedBox(width: 3), Text('等待对方', style: TextStyle(fontSize: 11, color: Colors.orange))])
          else
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 14, color: Colors.green), SizedBox(width: 3), Text('已添加', style: TextStyle(fontSize: 11, color: Colors.green))]),
        ],
      ),
    );
  }

  List<Widget> _buildContactList(ContactProvider contactProvider) {
    final contacts = contactProvider.contacts;
    final groupedContacts = contactProvider.groupedContacts;

    if (contacts.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('暂无联系人', style: TextStyle(color: Colors.grey[400], fontSize: 14))))];
    }

    if (_searchText.isNotEmpty) {
      return _buildSearchResults(contacts);
    }

    return _buildGroupedContactList(groupedContacts);
  }

  List<Widget> _buildSearchResults(List<dynamic> contacts) {
    final filtered = contacts.where((c) {
      final name = c.nickname?.isNotEmpty == true ? c.nickname : (c.username ?? '');
      final searchLower = _searchText.toLowerCase();
      return name.toLowerCase().contains(searchLower) || (c.username ?? '').toLowerCase().contains(searchLower);
    }).toList();

    if (filtered.isEmpty) {
      return [
        Padding(padding: const EdgeInsets.all(32), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
          SizedBox(height: 12),
          Text('无匹配结果', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          SizedBox(height: 4),
          Text('尝试其他关键词', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ])))
      ];
    }

    return [
      Padding(padding: const EdgeInsets.only(left: 56, top: 12, bottom: 8), child: Text('搜索结果 (${filtered.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor))),
      ...filtered.map((c) => _buildContactItem(c)),
    ];
  }

  List<Widget> _buildGroupedContactList(Map<String, List<UserModel>> groupedContacts) {
    List<Widget> result = [];
    for (final entry in groupedContacts.entries) {
      result.add(_buildGroupHeader(entry.key, entry.value.length));
      result.addAll(entry.value.map((contact) => _buildContactItem(contact)));
    }
    return result;
  }

  Widget _buildGroupHeader(String letter, int count) {
    _sectionKeys.putIfAbsent(letter, () => GlobalKey());
    return Container(key: _sectionKeys[letter], padding: const EdgeInsets.only(left: 56, top: 14, bottom: 6), child: Row(children: [
      Text(letter, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: 0.5)),
      SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Text('$count', style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor))),
    ]));
  }

  Widget _buildAlphabetIndex(List<String> letters) {
    return Container(width: 28, padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(14)), child: ListView.builder(itemCount: letters.length, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemBuilder: (context, index) {
      final letter = letters[index];
      return InkWell(onTap: () => _scrollToLetter(letter), child: Container(height: 22, alignment: Alignment.center, child: Text(letter, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor.withOpacity(0.7)))));
    }));
  }

  void _scrollToLetter(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(key!.currentContext!, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.0);
  }

  String _getRequestType(Map<String, dynamic> request) {
    final toUserId = request['toUserId']?.toString();
    final status = request['status']?.toString() ?? '0';
    if (_currentUserId == null) return 'unknown';
    if (status == '1') return 'accepted';
    final currentUserIdStr = _currentUserId.toString();
    if (toUserId == currentUserIdStr) return 'received';
    return 'sent';
  }

  List<Map<String, dynamic>> _filterRequestsByType(List<Map<String, dynamic>> requests, String type) =>
      requests.where((r) => _getRequestType(r) == type).toList();

  Widget _buildExpandableSection({
    required IconData icon,
    required String title,
    int? count,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 22, color: Colors.grey[600])),
            SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor, fontWeight: FontWeight.w500))),
            if (count != null) Text('$count', style: TextStyle(fontSize: 13, color: Colors.grey[500])) else Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem(dynamic contact) {
    final name = contact.nickname?.isNotEmpty == true ? contact.nickname : (contact.username ?? '未知用户');

    return InkWell(
      onTap: () {
        final realUserId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
        debugPrint('👆[DesktopContactsPanel] 点击联系人: id=${contact.id}, userId=$realUserId, name=$name');
        final layoutProvider = Provider.of<LayoutProvider>(context, listen: false);
        layoutProvider.selectContact(UserModel(id: contact.id, username: contact.username ?? '', nickname: contact.nickname ?? '', avatar: contact.avatar, imUserId: (realUserId > 0) ? realUserId.toString() : contact.imUserId));
      },
      onLongPress: () => _showContactContextMenu(contact, context),
      hoverColor: AppTheme.primaryColor.withOpacity(0.04),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(imageUrl: contact.avatar, name: name, size: 46),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimaryColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              if ((contact.username ?? '').isNotEmpty && contact.username != contact.nickname)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(contact.username ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ])),
            Icon(Icons.more_vert, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showContactContextMenu(dynamic contact, BuildContext context) {
    final name = contact.nickname?.isNotEmpty == true ? contact.nickname : (contact.username ?? '未知用户');
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(overlay.size.width * 0.3, overlay.size.height * 0.3, overlay.size.width * 0.3, overlay.size.height * 0.3),
      items: [
        PopupMenuItem<String>(value: 'chat', child: ListTile(leading: Icon(Icons.chat_bubble_outline, color: AppTheme.primaryColor), title: const Text('发送消息'), dense: true)),
        PopupMenuItem<String>(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline, color: Colors.blue), title: const Text('查看资料'), dense: true)),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AppTheme.errorColor), title: Text('删除好友', style: TextStyle(color: AppTheme.errorColor)), dense: true)),
      ],
    ).then((value) {
      if (value == 'chat') {
        final realUserId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
        final contactId = realUserId.toString();
        final layoutProvider = Provider.of<LayoutProvider>(context, listen: false);
        layoutProvider.selectNavigation(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          layoutProvider.selectConversation(contactId, name, false);
          Provider.of<ChatProvider>(context, listen: false).setCurrentConversation(ConversationModel(id: contactId, targetId: realUserId, name: name, isGroup: false, participantIds: []));
        });
      } else if (value == 'delete') {
        _confirmDeleteContact(contact, name);
      }
    });
  }

  void _confirmDeleteContact(dynamic contact, String name) {
    showDialog(context: context, builder: (BuildContext dialogContext) {
      return AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text('确认删除'), content: Text('确定要删除好友 "$name" 吗？\n删除后将无法看到对方的动态和消息记录。'), actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text('取消', style: TextStyle(color: Colors.grey[600]))),
        TextButton(onPressed: () { Navigator.of(dialogContext).pop(); final realUserId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0; _deleteContact(realUserId.toString(), name); }, style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('删除')),
      ]);
    });
  }

  Future<void> _deleteContact(String? contactId, String name) async {
    if (contactId == null || contactId.isEmpty) return;
    try {
      await context.read<ContactProvider>().deleteFriend(contactId);
      if (mounted) _showSuccessSnackBar('✅ 已删除好友 $name');
    } catch (e) {
      if (mounted) _showErrorSnackBar('❌ 删除失败: $e');
    }
  }

  Future<void> _acceptRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().acceptFriendRequestWithString(friendId.toString());
      if (mounted) _showSuccessSnackBar('✅ 已接受好友请求');
    } catch (e) {
      if (mounted) _showErrorSnackBar('❌ 操作失败: $e');
    }
  }

  Future<void> _rejectRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().rejectFriendRequestWithString(friendId.toString());
      if (mounted) _showSuccessSnackBar('已拒绝好友请求');
    } catch (e) {
      if (mounted) _showErrorSnackBar('操作失败: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    try { ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: AppTheme.successColor)); } catch (_) {}
  }

  void _showErrorSnackBar(String message) {
    try { ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: AppTheme.errorColor)); } catch (_) {}
  }
}

/// 添加好友独立弹窗
class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _errorMsg;
  List<UserModel> _searchResults = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() { _isSearching = true; _errorMsg = null; _searchResults = []; });

    try {
      final contactProvider = context.read<ContactProvider>();
      await contactProvider.searchUsers(keyword);

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _searchResults = contactProvider.searchResults;
      });
    } catch (e) {
      if (mounted) setState(() { _isSearching = false; _errorMsg = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      child: Container(
        width: 440,
        constraints: BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('添加朋友', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor)),
                IconButton(icon: Icon(Icons.close, size: 20, color: Colors.grey[500]), tooltip: '关闭', onPressed: () => Navigator.of(context).pop(), visualDensity: VisualDensity.compact),
              ]),
            ),

            // 搜索区域
            Padding(padding: const EdgeInsets.all(20), child: Row(children: [
              Expanded(child: TextField(controller: _searchController, autofocus: true, onSubmitted: (_) => _onSearch(), style: TextStyle(fontSize: 14), decoration: InputDecoration(hintText: '搜索微信号或手机号', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14), prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
              SizedBox(width: 10),
              ElevatedButton(onPressed: _isSearching ? null : _onSearch, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10)), child: _isSearching ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('搜索')),
            ])),

            // 错误提示
            if (_errorMsg != null)
              Padding(padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8), child: Text(_errorMsg!, style: TextStyle(fontSize: 13, color: AppTheme.errorColor))),

            // 搜索结果列表
            if (_searchResults.isNotEmpty || _isSearching)
              Expanded(child: Container(
                constraints: BoxConstraints(maxHeight: 280),
                child: _isSearching
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator()))
                    : ListView.separated(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _searchResults.length, separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: Colors.grey.shade100), itemBuilder: (ctx, i) => _buildSearchResultItem(_searchResults[i])),
              ))
            else if (!_isSearching && _searchResults.isEmpty && _searchController.text.isNotEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off, size: 40, color: Colors.grey[300]),
                SizedBox(height: 8),
                Text('未找到该用户', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              ])))
            else
              Padding(padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16), child: Align(alignment: Alignment.centerLeft, child: Text('输入对方的微信号或手机号进行搜索', style: TextStyle(fontSize: 12, color: Colors.grey[400])))),
          ],
        ),
      ),
    );
  }

  /// 搜索结果条目
  Widget _buildSearchResultItem(UserModel user) {
    final displayName = user.nickname.isNotEmpty ? user.nickname : user.username;
    return InkWell(onTap: () async {
      try {
        await context.read<ContactProvider>().sendFriendRequest(int.tryParse(user.id) ?? 0);
        if (mounted) Navigator.of(context).pop();
      } catch (e) { debugPrint('发送好友请求失败: $e'); }
    }, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      AvatarWidget(imageUrl: user.avatar, name: displayName, size: 44),
      SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        SizedBox(height: 2),
        Text(user.username, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ])),
      if (user.friendStatus == 0)
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppTheme.primaryColor), child: Text('添加', style: TextStyle(fontSize: 12, color: Colors.white)))
      else if (user.friendStatus == 1)
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.orange.withOpacity(0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.access_time, size: 13, color: Colors.orange), SizedBox(width: 4), Text('已请求', style: TextStyle(fontSize: 11, color: Colors.orange))]))
      else
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.green.withOpacity(0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 15, color: Colors.green), SizedBox(width: 4), Text('已是好友', style: TextStyle(fontSize: 11, color: Colors.green))])),
    ])));
  }
}
