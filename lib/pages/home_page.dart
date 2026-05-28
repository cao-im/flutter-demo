import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/conversation_list_page.dart';
import '../pages/contacts_page.dart';
import '../pages/profile_page.dart';
import '../providers/contact_provider.dart';
import '../providers/chat_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
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
}
