import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/user_model.dart';
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
  late ScrollController _scrollController;
  Map<double, String> _sectionOffsets = {};
  String? _currentHighlightLetter;
  bool _showLetterHint = false;
  String _hintLetter = '';

  static const double _specialItemHeight = 56.0;
  static const double _sectionHeaderHeight = 32.0;
  static const double _contactItemHeight = 64.0;

  /// 完整的字母索引列表：# + A-Z
  static const List<String> _fullAlphabet = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ContactProvider>(context, listen: false);
      provider.startListening();
      provider.loadContacts();
      provider.loadFriendRequests();
      _calculateSectionOffsets(provider.groupedContacts);
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final groupedContacts =
        Provider.of<ContactProvider>(context, listen: false).groupedContacts;
    if (groupedContacts.isEmpty || _sectionOffsets.isEmpty) return;

    final offset = _scrollController.offset;
    String? currentLetter;

    final sortedEntries = _sectionOffsets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (int i = sortedEntries.length - 1; i >= 0; i--) {
      if (offset >= sortedEntries[i].key - 10) {
        currentLetter = sortedEntries[i].value;
        break;
      }
    }

    if (currentLetter != _currentHighlightLetter) {
      setState(() {
        _currentHighlightLetter = currentLetter;
      });
    }
  }

  void _calculateSectionOffsets(Map<String, List<UserModel>> groupedContacts) {
    final offsets = <double, String>{};
    double currentOffset = _specialItemHeight * 2 + 8.0;

    for (final entry in groupedContacts.entries) {
      offsets[currentOffset] = entry.key;
      currentOffset += _sectionHeaderHeight +
          (entry.value.length * _contactItemHeight);
    }

    setState(() {
      _sectionOffsets = offsets;
    });
  }

  void _onIndexBarTap(String letter) {
    setState(() {
      _showLetterHint = true;
      _hintLetter = letter;
    });

    for (final entry in _sectionOffsets.entries) {
      if (entry.value == letter) {
        _scrollController.animateTo(
          entry.key,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
        break;
      }
    }
  }

  void _onIndexBarDragUpdate(double dy, double totalHeight,
      List<String> letters) {
    final index = (dy / totalHeight * letters.length).floor().clamp(
          0,
          letters.length - 1,
        );
    final letter = letters[index];
    if (letter != _hintLetter || !_showLetterHint) {
      setState(() {
        _showLetterHint = true;
        _hintLetter = letter;
      });
      _onIndexBarTap(letter);
    }
  }

  void _onIndexBarEnd() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _showLetterHint = false;
        });
      }
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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_sectionOffsets.isEmpty ||
                _sectionOffsets.length !=
                    contactProvider.groupedContacts.length) {
              _calculateSectionOffsets(contactProvider.groupedContacts);
            }
          });

          return Stack(
            children: [
              _buildContent(contactProvider),
              Positioned(
                right: 0,
                top: MediaQuery.of(context).padding.top +
                    kToolbarHeight +
                    8,
                bottom: MediaQuery.of(context).padding.bottom + 8,
                child: _IndexBar(
                  letters: _fullAlphabet,
                  existingLetters: contactProvider.groupedContacts.keys.toSet(),
                  highlightedLetter: _currentHighlightLetter,
                  onLetterTap: _onIndexBarTap,
                  onDragUpdate: _onIndexBarDragUpdate,
                  onDragEnd: _onIndexBarEnd,
                ),
              ),
              if (_showLetterHint) _buildLetterHint(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(ContactProvider contactProvider) {
    final groupedContacts = contactProvider.groupedContacts;
    final hasContacts = groupedContacts.isNotEmpty;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildSpecialItem(
                Icons.person_add_outlined,
                '新的朋友',
                () {
                  Provider.of<ContactProvider>(context, listen: false)
                      .markFriendRequestsAsRead();
                  Navigator.pushNamed(context, AppRouter.newFriends);
                },
                badgeCount: contactProvider.unreadFriendRequestCount,
              ),
              _buildSpecialItem(Icons.group_outlined, '群聊', () {
                Navigator.pushNamed(context, AppRouter.groupCreate);
              }),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ),
        ),
        if (hasContacts)
          ..._buildGroupedSlivers(groupedContacts)
        else if (!contactProvider.isLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无联系人',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildGroupedSlivers(
      Map<String, List<UserModel>> groupedContacts) {
    final slivers = <Widget>[];

    for (final entry in groupedContacts.entries) {
      slivers.add(SliverPersistentHeader(
        pinned: true,
        delegate: _SectionHeaderDelegate(
          title: entry.key,
          height: _sectionHeaderHeight,
        ),
      ));

      slivers.add(SliverList.builder(
        itemCount: entry.value.length,
        itemBuilder: (context, index) {
          final contact = entry.value[index];
          return _buildContactItem(contact);
        },
      ));
    }

    return slivers;
  }

  Widget _buildSpecialItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    int badgeCount = 0,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _specialItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      color: AppTheme.primaryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Icon(Icons.chevron_right,
                      color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(UserModel contact) {
    final name = contact.nickname.isNotEmpty
        ? contact.nickname
        : (contact.username.isNotEmpty ? contact.username : '未知用户');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final contactId = int.tryParse(contact.imUserId ?? contact.id) ?? int.tryParse(contact.id) ?? 0;
          Navigator.pushNamed(
            context,
            AppRouter.chat,
            arguments: {
              'conversationId': contactId > 0 ? '$contactId' : '',
              'conversationName': name,
              'isGroup': false,
              'targetId': contactId, // 直接传真正的用户ID
            },
          );
        },
        onLongPress: () => _showContactMenu(contact),
        child: SizedBox(
          height: _contactItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                AvatarWidget(imageUrl: contact.avatar, name: name, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.username,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContactMenu(UserModel contact) {
    final name = contact.nickname.isNotEmpty
        ? contact.nickname
        : contact.username;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除联系人',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteContact(contact, name);
                  },
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteContact(UserModel contact, String name) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('删除联系人'),
          content: Text('确定要删除联系人「$name」吗？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('删除',
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                final contactProvider = Provider.of<ContactProvider>(
                    context,
                    listen: false);
                contactProvider.deleteFriend(int.tryParse(contact.imUserId ?? contact.id)?.toString() ?? contact.id);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已删除联系人 $name'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );

                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    _calculateSectionOffsets(
                        contactProvider.groupedContacts);
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLetterHint() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _hintLetter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IndexBar extends StatelessWidget {
  final List<String> letters;
  final Set<String> existingLetters;
  final String? highlightedLetter;
  final ValueChanged<String> onLetterTap;
  final Function(double dy, double totalHeight, List<String> letters)
      onDragUpdate;
  final VoidCallback onDragEnd;

  const _IndexBar({
    required this.letters,
    required this.existingLetters,
    this.highlightedLetter,
    required this.onLetterTap,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (letters.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onVerticalDragStart: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localPosition = box.globalToLocal(details.globalPosition);
        onDragUpdate(localPosition.dy, box.size.height, letters);
      },
      onVerticalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localPosition = box.globalToLocal(details.globalPosition);
        onDragUpdate(localPosition.dy, box.size.height, letters);
      },
      onVerticalDragEnd: (_) => onDragEnd(),
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localPosition = box.globalToLocal(details.globalPosition);
        final index = (localPosition.dy / box.size.height * letters.length)
            .floor()
            .clamp(0, letters.length - 1);
        onLetterTap(letters[index]);
        Future.delayed(const Duration(milliseconds: 300), () => onDragEnd());
      },
      child: Container(
        width: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: letters.map((letter) {
            final isHighlighted = letter == highlightedLetter;
            final hasContacts = existingLetters.contains(letter);
            return Padding(
              padding: EdgeInsets.zero,
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                  color: isHighlighted
                      ? AppTheme.primaryColor
                      : (hasContacts ? Colors.grey[600] : Colors.grey[300]),
                ),
              ),
            );
          }).toList(),
        ),
        ),
      ),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final double height;

  _SectionHeaderDelegate({
    required this.title,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: height,
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.only(left: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return title != oldDelegate.title || height != oldDelegate.height;
  }
}
