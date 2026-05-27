import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/conversation_list_page.dart';
import '../pages/contacts_page.dart';
import '../pages/profile_page.dart';
import '../providers/connection_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/chat_provider.dart';
import '../services/storage_service.dart';
import '../widgets/badge_navigation_bar_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const ConversationListPage(),
    const ContactsPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().startListening();
      context.read<ChatProvider>().startListening();
    });
  }

  /// ✅ 查看 Drift 数据（调试功能）- TODO: 后续可添加 Drift 数据查看
  Future<void> _viewHiveData() async {
    // TODO: 实现 Drift 数据库查看功能
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📊 数据库查看功能开发中...'),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// ✅ 清空所有本地存储数据（调试功能）
  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('确认清空数据', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          '此操作将删除所有本地存储的：\n\n'
          '• 📨 聊天消息\n'
          '• 💬 会话列表\n'
          '• ⚙️ 应用设置\n\n'
          '⚠️ 此操作不可恢复！',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      // TODO: 通过 StorageFactory 清空数据
      // await HiveViewer.clearAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ 数据清空功能开发中...'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 清空失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Consumer<ConnectionProvider>(
            builder: (context, connectionProvider, _) {
              final state = connectionProvider.state;
              final error = connectionProvider.errorMessage;

              if (connectionProvider.isConnected) {
                return const SizedBox.shrink();
              }

              if (state == ImConnectionState.connecting ||
                  state == ImConnectionState.reconnecting) {
                return Container(
                  color: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state == ImConnectionState.connecting
                            ? '正在连接...'
                            : '正在重连...',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              if (error != null && error.isNotEmpty) {
                return Container(
                  color: Colors.red[400],
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error.length > 50 ? '${error.substring(0, 47)}...' : error,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _retryConnect(connectionProvider),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('重试', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                color: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text('未连接', style: TextStyle(color: Colors.white, fontSize: 12)),
                    GestureDetector(
                      onTap: () => _retryConnect(connectionProvider),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('连接', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _pages),
          ),
        ],
      ),

      // ✅ 调试浮动按钮组：查看/导出/清空本地存储数据
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 清空数据按钮（红色，危险操作）
          FloatingActionButton.extended(
            onPressed: _clearAllData,
            icon: const Icon(Icons.delete_forever),
            label: const Text('清空数据'),
            tooltip: '清空所有本地存储数据（消息、会话、设置）',
            backgroundColor: Colors.red[400],
            foregroundColor: Colors.white,
            heroTag: 'hive_clear',
          ),
          const SizedBox(height: 10),
          // 查看数据按钮（紫色）
          FloatingActionButton.extended(
            onPressed: _viewHiveData,
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('查看数据'),
            tooltip: '查看 Hive 本地存储数据',
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            heroTag: 'hive_view',
          ),
        ],
      ),

      bottomNavigationBar: Consumer2<ChatProvider, ContactProvider>(
        builder: (context, chatProvider, contactProvider, _) {
          final messageUnreadCount = chatProvider.totalUnreadCount;
          final contactUnreadCount = contactProvider.unreadFriendRequestCount;

          return BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: [
              BadgeNavigationBarHelper.create(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble),
                label: '消息',
                unreadCount: messageUnreadCount,
              ),
              BadgeNavigationBarHelper.create(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: '通讯录',
                unreadCount: contactUnreadCount,
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _retryConnect(ConnectionProvider provider) async {
    final token = await StorageService.getImToken() ?? await StorageService.getToken();
    final userIdStr = await StorageService.getUserId();
    if (token == null) return;

    if (!provider.isInitialized) {
      try {
        debugPrint('📍[HomePage] SDK未初始化，先初始化...');
        await provider.initialize('ws://192.168.0.138/api/ws');
      } catch (e) {
        debugPrint('❌[HomePage] 初始化失败: $e');
        return;
      }
    }

    if (provider.isInitialized) {
      final uid = int.tryParse(userIdStr ?? '') ?? 0;
      await provider.connect(token, userId: uid);
    } else {
      debugPrint('❌[HomePage] 初始化后仍不可用，无法连接');
    }
  }
}
