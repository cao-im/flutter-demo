import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/avatar_widget.dart';

class GroupListPage extends StatefulWidget {
  const GroupListPage({super.key});

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  List<dynamic> _groups = [];
  bool _isLoading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) throw Exception('未登录');
      final userId = int.tryParse(imUserIdStr);
      if (userId == null || userId <= 0) throw Exception('用户ID无效');

      final apiService = ApiService();
      final data = await apiService.getUserGroups(userId);
      if (mounted) setState(() => _groups = data);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群聊'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: '发起群聊',
            onPressed: () => Navigator.pushNamed(context, '/group-create'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMsg != null && _groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('加载失败', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            Text(_errorMsg!, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGroups,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('暂无群组', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 8),
            Text('点击右上角发起群聊', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGroups,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _groups.length,
        separatorBuilder: (_, __) => Divider(height: 1, indent: 56, endIndent: 16, color: Colors.grey[200]),
        itemBuilder: (context, index) => _buildGroupItem(_groups[index]),
      ),
    );
  }

  Widget _buildGroupItem(dynamic group) {
    final groupId = group['id']?.toString() ?? '';
    final groupName = group['name']?.toString() ?? '未命名群组';
    final avatar = group['avatar'];

    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/chat',
        arguments: {
          'conversationId': groupId,
          'conversationName': groupName,
          'isGroup': true,
          'targetId': int.tryParse(groupId) ?? 0,
        },
      ),
      onLongPress: () => _showGroupMenu(groupName, groupId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AvatarWidget(imageUrl: avatar, name: groupName, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showGroupMenu(String groupName, String groupId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ListTile(leading: Icon(Icons.chat_bubble_outline), title: const Text('进入聊天'), onTap: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/chat', arguments: {'conversationId': groupId, 'conversationName': groupName, 'isGroup': true, 'targetId': int.tryParse(groupId) ?? 0}); }),
              ListTile(leading: Icon(Icons.info_outline), title: const Text('群信息'), onTap: () { Navigator.pop(ctx); }),
            ],
          ),
        ),
      ),
    );
  }
}
