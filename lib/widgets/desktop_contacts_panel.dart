import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/contact_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/layout_provider.dart';
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
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索',
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildContactsContent() {
    return Consumer<ContactProvider>(
      builder: (context, contactProvider, _) {
        return ListView(padding: EdgeInsets.zero, children: [
          _buildSpecialSection(icon: Icons.person_add_outlined, title: '新的朋友', badgeCount: contactProvider.unreadFriendRequestCount, onTap: () => setState(() => _currentView = _PanelView.newFriends)),
          _buildExpandableSection(icon: Icons.group_outlined, title: '群聊', count: null, isExpanded: false, onTap: () {}),
          _buildExpandableSection(icon: Icons.article_outlined, title: '公众号', count: null, isExpanded: false, onTap: () {}),
          _buildExpandableSection(icon: Icons.support_agent_outlined, title: '服务号', count: null, isExpanded: false, onTap: () {}),
          Divider(height: 1, indent: 56),
          _buildContactHeader(contactProvider.contacts.length),
          ..._buildContactList(contactProvider),
        ]);
      },
    );
  }

  Widget _buildNewFriendsContent() {
    return Consumer<ContactProvider>(
      builder: (context, contactProvider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) { contactProvider.markFriendRequestsAsRead(); });
        final requests = contactProvider.friendRequests;

        if (requests.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mail_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text('暂无好友请求', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            SizedBox(height: 8),
            Text('当有人添加你为好友时会显示在这里', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ]));
        }

        final receivedRequests = _filterRequestsByType(requests, 'received');
        final sentRequests = _filterRequestsByType(requests, 'sent');
        final acceptedRequests = _filterRequestsByType(requests, 'accepted');

        return ListView(padding: EdgeInsets.zero, children: [
          InkWell(onTap: () => setState(() => _currentView = _PanelView.contacts), child: Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('返回通讯录', style: TextStyle(fontSize: 15, color: AppTheme.primaryColor)),
          ]))),
          Divider(height: 1, indent: 12, endIndent: 12),
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
          SizedBox(height: 20),
        ]);
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

  List<Map<String, dynamic>> _filterRequestsByType(List<Map<String, dynamic>> requests, String type) => requests.where((r) => _getRequestType(r) == type).toList();

  Widget _buildSpecialSection({required IconData icon, required String title, int? badgeCount, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
      SizedBox(width: 44), Icon(icon, size: 22, color: AppTheme.primaryColor), SizedBox(width: 14),
      Expanded(child: Text(title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor))),
      if (badgeCount != null && badgeCount! > 0)
        Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.errorColor, borderRadius: BorderRadius.circular(10)), child: Text('$badgeCount', style: TextStyle(fontSize: 11, color: Colors.white)))
      else
        Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
    ])));
  }

  Widget _buildExpandableSection({required IconData icon, required String title, int? count, required bool isExpanded, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
      SizedBox(width: 44), Icon(icon, size: 22, color: Colors.grey[600]), SizedBox(width: 14),
      Expanded(child: Text(title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor))),
      if (count != null) Text('$count', style: TextStyle(fontSize: 13, color: Colors.grey[500])) else Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
    ])));
  }

  Widget _buildContactHeader(int totalCount) => Padding(padding: EdgeInsets.only(left: 56, top: 8, bottom: 6), child: Text('联系人', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)));

  List<Widget> _buildContactList(ContactProvider provider) {
    final contacts = provider.contacts;
    if (_searchText.isNotEmpty) {
      final filtered = contacts.where((c) {
        final name = c.nickname?.isNotEmpty == true ? c.nickname : (c.username ?? '');
        return name.toLowerCase().contains(_searchText.toLowerCase());
      }).toList();
      if (filtered.isEmpty) return [Padding(padding: EdgeInsets.all(20), child: Center(child: Text('无匹配结果', style: TextStyle(color: Colors.grey[400]))))];
      return filtered.map((c) => _buildContactItem(c)).toList();
    }
    if (contacts.isEmpty) return [Padding(padding: EdgeInsets.all(20), child: Center(child: Text('暂无联系人', style: TextStyle(color: Colors.grey[400]))))];
    final grouped = <String, List<dynamic>>{};
    for (final contact in contacts) {
      final name = contact.nickname?.isNotEmpty == true ? contact.nickname : (contact.username ?? '?');
      final firstChar = name.substring(0, 1).toUpperCase();
      if (!grouped.containsKey(firstChar)) grouped[firstChar] = [];
      grouped[firstChar]!.add(contact);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    List<Widget> result = [];
    for (final key in sortedKeys) {
      result.add(Padding(padding: EdgeInsets.only(left: 56, top: 12, bottom: 4), child: Text(key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor))));
      result.addAll(grouped[key]!.map((c) => _buildContactItem(c)));
    }
    return result;
  }

  Widget _buildContactItem(dynamic contact) {
    final name = contact.nickname?.isNotEmpty == true ? contact.nickname : (contact.username ?? '未知用户');
    return InkWell(onTap: () => Provider.of<LayoutProvider>(context, listen: false).selectConversation(contact.id ?? '', name, false), child: Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
      AvatarWidget(imageUrl: contact.avatar, name: name, size: 40), SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        if ((contact.username ?? '').isNotEmpty && contact.username != contact.nickname)
          Text(contact.username ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ])));
  }

  Widget _buildNewFriendsSectionHeader(String title, int count) => Padding(padding: EdgeInsets.only(left: 56, top: 12, bottom: 4), child: Row(children: [
    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
    SizedBox(width: 8),
    Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Text('$count', style: TextStyle(fontSize: 12, color: AppTheme.primaryColor))),
  ]));

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

    return Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)), child: Padding(padding: EdgeInsets.all(10), child: Row(children: [
      AvatarWidget(imageUrl: avatar, name: displayName, size: 44), SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        SizedBox(height: 2),
        Text(isPendingReceived ? '$fromUsername 请求添加你为好友' : isPendingSent ? '已向 $fromUsername 发送请求' : '$fromUsername 已成为好友', style: TextStyle(fontSize: 12, color: isPendingReceived ? AppTheme.primaryColor : Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      if (isPendingReceived) ...[
        InkWell(onTap: () => _rejectRequest(fromUserId), borderRadius: BorderRadius.circular(16), child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.5))), child: Text('拒绝', style: TextStyle(fontSize: 12, color: AppTheme.errorColor)))),
        SizedBox(width: 6),
        InkWell(onTap: () => _acceptRequest(fromUserId), borderRadius: BorderRadius.circular(16), child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppTheme.primaryColor), child: Text('接受', style: TextStyle(fontSize: 12, color: Colors.white)))),
      ] else if (isPendingSent)
        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.orange.withValues(alpha: 0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.access_time, size: 12, color: Colors.orange), SizedBox(width: 3), Text('等待对方', style: TextStyle(fontSize: 11, color: Colors.orange))]))
      else
        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.green.withValues(alpha: 0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 14, color: Colors.green), SizedBox(width: 3), Text('已添加', style: TextStyle(fontSize: 11, color: Colors.green))])),
    ]))));
  }

  Future<void> _acceptRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().acceptFriendRequestWithString(friendId.toString());
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('✅ 已接受好友请求'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('❌ 操作失败: $e'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(dynamic friendId) async {
    try {
      await context.read<ContactProvider>().rejectFriendRequestWithString(friendId.toString());
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('已拒绝好友请求'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
}
