import 'package:flutter/material.dart';
import '../pages/splash_page.dart';
import '../pages/login_page.dart';
import '../pages/register_page.dart';
import '../pages/home_page.dart';
import '../pages/chat_page.dart';
import '../pages/group_create_page.dart';
import '../pages/group_chat_page.dart';
import '../pages/group_list_page.dart';
import '../pages/search_add_friend_page.dart';
import '../pages/new_friends_page.dart';

class AppRouter {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String groupCreate = '/group-create';
  static const String groupList = '/group-list';
  static const String groupChat = '/group-chat';
  static const String searchAddFriend = '/search-add-friend';
  static const String newFriends = '/new-friends';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashPage());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterPage());
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case chat:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: args?['conversationId'] ?? '',
            conversationName: args?['conversationName'] ?? '',
            isGroup: args?['isGroup'] ?? false,
            targetId: args?['targetId'] ?? 0,
          ),
        );
      case groupCreate:
        return MaterialPageRoute(
            builder: (_) => const GroupCreatePage());
      case groupList:
        return MaterialPageRoute(
            builder: (_) => const GroupListPage());
      case groupChat:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => GroupChatPage(
            groupId: args?['groupId'] ?? '',
            groupName: args?['groupName'] ?? '',
          ),
        );
      case searchAddFriend:
        return MaterialPageRoute(
          builder: (_) => const SearchAddFriendPage(),
        );
      case newFriends:
        return MaterialPageRoute(
          builder: (_) => const NewFriendsPage(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
