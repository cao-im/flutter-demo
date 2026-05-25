import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/contact_provider.dart';
import '../router/app_router.dart';
import '../widgets/avatar_widget.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ContactProvider>(context, listen: false);
      provider.loadContacts();
      provider.loadFriendRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.pushNamed(context, AppRouter.searchAddFriend);
            },
          ),
        ],
      ),
      body: Consumer<ContactProvider>(
        builder: (context, contactProvider, _) {
          if (contactProvider.isLoading && contactProvider.contacts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            children: [
              _buildSpecialItem(
                Icons.person_add,
                '新的朋友',
                () {
                  Provider.of<ContactProvider>(context, listen: false)
                      .markFriendRequestsAsRead();
                  Navigator.pushNamed(context, AppRouter.newFriends);
                },
                badgeCount: contactProvider.unreadFriendRequestCount,
              ),
              _buildSpecialItem(Icons.group, '群组', () {
                Navigator.pushNamed(context, AppRouter.groupCreate);
              }),
              const Divider(height: 1),
              ...contactProvider.contacts.map(
                (contact) => _buildContactItem(contact),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpecialItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    int badgeCount = 0,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem(dynamic contact) {
    final name = contact.nickname?.isNotEmpty == true
        ? contact.nickname
        : (contact.username ?? '未知用户');
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRouter.chat,
          arguments: {
            'conversationId': contact.id ?? '',
            'conversationName': name,
            'isGroup': false,
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(imageUrl: contact.avatar, name: name, size: 44),
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
                  Text(
                    contact.username ?? '',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
