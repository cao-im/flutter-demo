import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/conversation_list_page.dart';
import '../pages/contacts_page.dart';
import '../pages/profile_page.dart';
import '../providers/connection_provider.dart';
import '../providers/contact_provider.dart';
import '../services/storage_service.dart';

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
    });
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: '消息',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: '通讯录',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
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
        await provider.initialize('ws://localhost/api/ws');
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
