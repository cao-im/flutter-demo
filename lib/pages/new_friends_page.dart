import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/contact_provider.dart';
import '../widgets/avatar_widget.dart';
import '../theme/app_theme.dart';

class NewFriendsPage extends StatefulWidget {
  const NewFriendsPage({super.key});

  @override
  State<NewFriendsPage> createState() => _NewFriendsPageState();
}

class _NewFriendsPageState extends State<NewFriendsPage> {
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentUserId();
      Provider.of<ContactProvider>(context, listen: false).loadFriendRequests();
    });
  }

  Future<void> _loadCurrentUserId() async {
    final userIdStr = await _getImUserId();
    if (userIdStr != null) {
      setState(() {
        _currentUserId = int.tryParse(userIdStr);
      });
    }
  }

  Future<String?> _getImUserId() async {
    try {
      final storage = await SharedPreferences.getInstance();
      return storage.getString('im_user_id');
    } catch (e) {
      return null;
    }
  }

  Future<void> _acceptRequest(int friendId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('接受好友请求'),
        content: const Text('确定要接受这个好友请求吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await context.read<ContactProvider>().acceptFriendRequest(friendId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已接受好友请求')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _rejectRequest(int friendId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拒绝好友请求'),
        content: const Text('确定要拒绝这个好友请求吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '拒绝',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await context.read<ContactProvider>().rejectFriendRequest(friendId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已拒绝好友请求')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失败: $e')),
          );
        }
      }
    }
  }

  String _getRequestType(Map<String, dynamic> request) {
    final userId = request['userId'];
    final friendId = request['friendId'];
    final status = request['status']?.toString() ?? '0';

    if (_currentUserId == null) return 'unknown';

    if (status == '1') {
      return 'accepted';
    }

    if (userId == _currentUserId) {
      return 'sent';
    } else {
      return 'received';
    }
  }

  String _getRequestTitle(String type) {
    switch (type) {
      case 'received':
        return '新的好友请求';
      case 'sent':
        return '我发起的好友请求';
      case 'accepted':
        return '已添加的好友';
      default:
        return '未知类型';
    }
  }

  String _getRequestSubtitle(String type, Map<String, dynamic> request) {
    final username = request['username']?.toString() ?? 
                    request['friendUsername']?.toString() ?? 
                    '未知用户';

    switch (type) {
      case 'received':
        return '$username 请求添加你为好友';
      case 'sent':
        return '你已向 $username 发送好友请求，等待对方同意';
      case 'accepted':
        return '你和 $username 已经是好友了';
      default:
        return '';
    }
  }

  List<Map<String, dynamic>> _filterRequestsByType(List<Map<String, dynamic>> requests, String type) {
    return requests.where((request) => _getRequestType(request) == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新的朋友'),
      ),
      body: Consumer<ContactProvider>(
        builder: (context, contactProvider, _) {
          final requests = contactProvider.friendRequests;

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mail_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无好友请求',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当有人添加你为好友时会显示在这里',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          final receivedRequests = _filterRequestsByType(requests, 'received');
          final sentRequests = _filterRequestsByType(requests, 'sent');
          final acceptedRequests = _filterRequestsByType(requests, 'accepted');

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (receivedRequests.isNotEmpty) ...[
                _buildSectionHeader('收到的好友请求', receivedRequests.length),
                ...receivedRequests.map((request) => _buildRequestItem(request)),
              ],
              if (sentRequests.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildSectionHeader('我发起的请求', sentRequests.length),
                ...sentRequests.map((request) => _buildRequestItem(request)),
              ],
              if (acceptedRequests.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildSectionHeader('已添加的好友', acceptedRequests.length),
                ...acceptedRequests.map((request) => _buildRequestItem(request)),
              ],
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> request) {
    final type = _getRequestType(request);
    final userId = request['userId'];
    final username = request['username']?.toString() ?? 
                    request['friendUsername']?.toString() ?? 
                    '未知用户';
    final nickname = request['nickname']?.toString() ?? 
                     request['friendNickname']?.toString() ?? '';
    final displayName = nickname.isNotEmpty ? nickname : username;
    final avatar = request['avatar'];

    final isPendingReceived = type == 'received';
    final isPendingSent = type == 'sent';
    final isAccepted = type == 'accepted';

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
              AvatarWidget(imageUrl: avatar, name: displayName, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getRequestSubtitle(type, request),
                      style: TextStyle(
                        fontSize: 13,
                        color: isPendingReceived ? AppTheme.primaryColor : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPendingReceived) ...[
                OutlinedButton.icon(
                  onPressed: () => _rejectRequest(userId),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('拒绝'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _acceptRequest(userId),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('接受'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ] else if (isPendingSent)
                Container(
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
                        '等待对方',
                        style: TextStyle(color: Colors.orange[400], fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.green[400]),
                      const SizedBox(width: 4),
                      Text(
                        '已添加',
                        style: TextStyle(color: Colors.green[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
