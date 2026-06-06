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

enum _PanelView { contacts, newFriends }

class _DesktopContactsPanelState extends State<DesktopContactsPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _PanelView _currentView = _PanelView.contacts;
  int? _currentUserId;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

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
          Expanded(child: _currentView == _PanelView.newFriends ? _buildNewFriendsContent() : _buildContactsContent()),
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
                  // ✅ 菜单项始终显示，不受联系人数量影响
                  _buildSpecialSection(
                    icon: Icons.person_add_outlined,
                    title: '新的朋友',
                    badgeCount: contactProvider.unreadFriendRequestCount,
                    onTap: () => setState(() => _currentView = _PanelView.newFriends),
                  ),
                  // ✅ 新增：搜索并添加好友（常驻入口）
                  _buildSpecialSection(
                    icon: Icons.person_search_outlined,
                    title: '添加好友',
                    badgeCount: null,
                    onTap: () => Navigator.of(context).pushNamed(AppRouter.searchAddFriend),
                  ),
                  _buildExpandableSection(icon: Icons.group_outlined, title: '群聊', count: null, isExpanded: false, onTap: () {}),
                  _buildExpandableSection(icon: Icons.article_outlined, title: '公众号', count: null, isExpanded: false, onTap: () {}),
                  _buildExpandableSection(icon: Icons.support_agent_outlined, title: '服务号', count: null, isExpanded: false, onTap: () {}),
                  Divider(height: 1, indent: 56, color: Colors.grey[200]),

                  // ✅ 联系人列表或空状态提示
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
                            // ✅ 添加"搜索添加好友"按钮
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pushNamed(AppRouter.searchAddFriend),
                              icon: const Icon(Icons.person_add, size: 20),
                              label: const Text('搜索并添加好友'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
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

  List<Widget> _buildContactList(ContactProvider contactProvider) {
    final contacts = contactProvider.contacts;
    final groupedContacts = contactProvider.groupedContacts;

    if (contacts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('暂无联系人', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ),
        )
      ];
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
      return name.toLowerCase().contains(searchLower) ||
             (c.username ?? '').toLowerCase().contains(searchLower);
    }).toList();

    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('无匹配结果', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                const SizedBox(height: 4),
                Text('尝试其他关键词', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ],
            ),
          ),
        )
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(left: 56, top: 12, bottom: 8),
        child: Text(
          '搜索结果 (${filtered.length})',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor),
        ),
      ),
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
    // 确保每个字母分组有对应的 GlobalKey
    _sectionKeys.putIfAbsent(letter, () => GlobalKey());

    return Container(
      key: _sectionKeys[letter],
      padding: const EdgeInsets.only(left: 56, top: 14, bottom: 6),
      child: Row(
        children: [
          Text(
            letter,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlphabetIndex(List<String> letters) {
    return Container(
      width: 28,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.builder(
        itemCount: letters.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final letter = letters[index];
          return InkWell(
            onTap: () => _scrollToLetter(letter),
            child: Container(
              height: 22,
              alignment: Alignment.center,
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor.withOpacity(0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _scrollToLetter(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext == null) return;

    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  Widget _buildNewFriendsContent() {
    return Consumer<ContactProvider>(
      builder: (context, contactProvider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          contactProvider.markFriendRequestsAsRead();
        });
        final requests = contactProvider.friendRequests;

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('暂无好友请求', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 8),
                Text('当有人添加你为好友时会显示在这里', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              ],
            ),
          );
        }

        final receivedRequests = _filterRequestsByType(requests, 'received');
        final sentRequests = _filterRequestsByType(requests, 'sent');
        final acceptedRequests = _filterRequestsByType(requests, 'accepted');

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              onTap: () => setState(() => _currentView = _PanelView.contacts),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text('返回通讯录', style: TextStyle(fontSize: 15, color: AppTheme.primaryColor)),
                  ],
                ),
              ),
            ),
            Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey[200]),
            if (receivedRequests.isNotEmpty) ...[
              _buildNewFriendsSectionHeader('收到的好友请求', receivedRequests.length),
              ...receivedRequests.map((r) => _buildRequestItem(r)),
            ],
            if (sentRequests.isNotEmpty) ...[
              _buildNewFriendsSectionHeader('我发起的请求', sentRequests.length),
              ...sentRequests.map((r) => _buildRequestItem(r)),
            ],
            if (acceptedRequests.isNotEmpty) ...[
              _buildNewFriendsSectionHeader('已添加的好友', acceptedRequests.length),
              ...acceptedRequests.map((r) => _buildRequestItem(r)),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
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

  Widget _buildSpecialSection({
    required IconData icon,
    required String title,
    int? badgeCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
              child: Icon(icon, size: 22, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor, fontWeight: FontWeight.w500),
              ),
            ),
            if (badgeCount != null && badgeCount! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badgeCount', style: const TextStyle(fontSize: 11, color: Colors.white)),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: Colors.grey[600]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor, fontWeight: FontWeight.w500),
              ),
            ),
            if (count != null)
              Text('$count', style: TextStyle(fontSize: 13, color: Colors.grey[500]))
            else
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
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
        final contactId = realUserId.toString();
        final layoutProvider = Provider.of<LayoutProvider>(context, listen: false);
        layoutProvider.selectConversation(contactId, name, false);
        debugPrint('👆[DesktopContactsPanel] 已调用 layoutProvider.selectConversation');

        // ✅ 同时设置 ChatProvider 的当前会话，确保发送消息时能正确获取
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        debugPrint('👆[DesktopContactsPanel] 准备设置 ChatProvider 当前会话: conversationId=$contactId, targetId=$realUserId');
        chatProvider.setCurrentConversation(
          ConversationModel(
            id: contactId,
            targetId: realUserId,
            name: name,
            isGroup: false,
            participantIds: [],
          ),
        );
        debugPrint('✅[DesktopContactsPanel] 联系人点击处理完成');
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((contact.username ?? '').isNotEmpty && contact.username != contact.nickname)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        contact.username ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
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
      position: RelativeRect.fromLTRB(
        overlay.size.width * 0.3,
        overlay.size.height * 0.3,
        overlay.size.width * 0.3,
        overlay.size.height * 0.3,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'chat',
          child: ListTile(
            leading: Icon(Icons.chat_bubble_outline, color: AppTheme.primaryColor),
            title: const Text('发送消息'),
            dense: true,
          ),
        ),
        PopupMenuItem<String>(
          value: 'profile',
          child: ListTile(
            leading: Icon(Icons.person_outline, color: Colors.blue),
            title: const Text('查看资料'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: AppTheme.errorColor),
            title: Text(
              '删除好友',
              style: TextStyle(color: AppTheme.errorColor),
            ),
            dense: true,
          ),
        ),
      ],
    ).then((value) {
      if (value == 'chat') {
        final realUserId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
        final contactId = realUserId.toString();
        Provider.of<LayoutProvider>(context, listen: false)
            .selectConversation(contactId, name, false);

        // ✅ 同时设置 ChatProvider 的当前会话
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        chatProvider.setCurrentConversation(
          ConversationModel(
            id: contactId,
            targetId: realUserId,
            name: name,
            isGroup: false,
            participantIds: [],
          ),
        );
      } else if (value == 'delete') {
        _confirmDeleteContact(contact, name);
      }
    });
  }

  void _confirmDeleteContact(dynamic contact, String name) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('确认删除'),
          content: Text('确定要删除好友 "$name" 吗？\n删除后将无法看到对方的动态和消息记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('取消', style: TextStyle(color: Colors.grey[600])),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                final realUserId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
                _deleteContact(realUserId.toString(), name);
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteContact(String? contactId, String name) async {
    if (contactId == null || contactId.isEmpty) return;

    try {
      await context.read<ContactProvider>().deleteFriend(contactId);

      if (mounted) {
        _showSuccessSnackBar('✅ 已删除好友 $name');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('❌ 删除失败: $e');
      }
    }
  }

  Widget _buildNewFriendsSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 16, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> request) {
    final type = _getRequestType(request);
    final fromUserId = request['fromUserId'];
    final fromUsername = request['fromUsername']?.toString() ?? '未知用户';
    final fromNickname = request['fromNickname']?.toString() ?? '';
    final displayName = fromNickname.isNotEmpty ? fromNickname : fromUsername;
    final avatar = type == 'received' ? request['fromAvatar'] : request['toAvatar'];

    final isPendingReceived = type == 'received';
    final isPendingSent = type == 'sent';
    final isAccepted = type == 'accepted';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AvatarWidget(imageUrl: avatar, name: displayName, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPendingReceived
                          ? '$fromUsername 请求添加你为好友'
                          : isPendingSent
                              ? '已向 $fromUsername 发送请求'
                              : '$fromUsername 已成为好友',
                      style: TextStyle(
                          fontSize: 13,
                          color: isPendingReceived ? AppTheme.primaryColor : Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isPendingReceived) ...[
                InkWell(
                  onTap: () => _rejectRequest(fromUserId),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.errorColor.withOpacity(0.5)),
                    ),
                    child: const Text('拒绝', style: TextStyle(fontSize: 12, color: AppTheme.errorColor)),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _acceptRequest(fromUserId),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: AppTheme.primaryColor,
                    ),
                    child: const Text('接受', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ),
              ] else if (isPendingSent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.orange.withOpacity(0.08),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 13, color: Colors.orange),
                      const SizedBox(width: 4),
                      const Text('等待对方', style: TextStyle(fontSize: 12, color: Colors.orange)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.green.withOpacity(0.08),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 15, color: Colors.green),
                      const SizedBox(width: 4),
                      const Text('已添加', style: TextStyle(fontSize: 12, color: Colors.green)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().acceptFriendRequestWithString(friendId.toString());
      if (mounted) {
        _showSuccessSnackBar('✅ 已接受好友请求');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('❌ 操作失败: $e');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    try {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (_) {
      // 忽略无 Scaffold 上下文的情况
    }
  }

  void _showErrorSnackBar(String message) {
    try {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } catch (_) {
      // 忽略无 Scaffold 上下文的情况
    }
  }

  Future<void> _rejectRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().rejectFriendRequestWithString(friendId.toString());
      if (mounted) {
        _showSuccessSnackBar('已拒绝好友请求');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('操作失败: $e');
      }
    }
  }
}
