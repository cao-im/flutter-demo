import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/contact_provider.dart';
import '../widgets/avatar_widget.dart';
import '../theme/app_theme.dart';

class SearchAddFriendPage extends StatefulWidget {
  const SearchAddFriendPage({super.key});

  @override
  State<SearchAddFriendPage> createState() => _SearchAddFriendPageState();
}

class _SearchAddFriendPageState extends State<SearchAddFriendPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Map<int, int> _friendStatusMap = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _friendStatusMap.clear();
    });

    try {
      await context.read<ContactProvider>().searchUsers(keyword.trim());
      _checkAllFriendsStatus();
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _checkAllFriendsStatus() async {
    final contactProvider = context.read<ContactProvider>();
    for (final user in contactProvider.searchResults) {
      final friendId = int.tryParse(user.id ?? '');
      if (friendId != null) {
        final status = await contactProvider.checkFriendStatus(friendId);
        if (mounted) {
          setState(() {
            _friendStatusMap[friendId] = status;
          });
        }
      }
    }
  }

  Future<void> _sendFriendRequest(dynamic user) async {
    final friendId = int.tryParse(user.id ?? '');
    if (friendId == null) return;

    try {
      await context.read<ContactProvider>().sendFriendRequest(friendId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('好友请求已发送')),
        );
        setState(() {
          _friendStatusMap[friendId] = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }

  Widget _buildActionButton(dynamic user) {
    final friendId = int.tryParse(user.id ?? '');
    if (friendId == null) return const SizedBox.shrink();

    final status = _friendStatusMap[friendId] ?? 0;

    if (status == 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '已添加',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    } else if (status == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: 14, color: Colors.orange[400]),
            const SizedBox(width: 4),
            Text(
              '已发送',
              style: TextStyle(color: Colors.orange[400], fontSize: 13),
            ),
          ],
        ),
      );
    } else {
      return ElevatedButton.icon(
        onPressed: () => _sendFriendRequest(user),
        icon: const Icon(Icons.person_add, size: 18),
        label: const Text('添加'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加好友'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '输入用户名或昵称搜索',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _performSearch,
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.search, color: AppTheme.primaryColor),
                  onPressed: () => _performSearch(_searchController.text),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ContactProvider>(
              builder: (context, contactProvider, _) {
                final results = contactProvider.searchResults;

                if (_isSearching && results.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!_isSearching && results.isEmpty && _searchController.text.isNotEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('未找到匹配的用户', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                if (results.isEmpty && _searchController.text.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('搜索用户并添加为好友', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final user = results[index];
                    return _buildUserItem(user);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserItem(dynamic user) {
    final name = user.nickname?.isNotEmpty == true ? user.nickname : user.username;
    final subtitle = '@${user.username ?? ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AvatarWidget(imageUrl: user.avatar, name: name, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              _buildActionButton(user),
            ],
          ),
        ),
      ),
    );
  }
}
