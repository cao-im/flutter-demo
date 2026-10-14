import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';
import '../providers/contact_provider.dart';
import '../router/app_router.dart';

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  List<String> _selectedMembers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contactProvider = Provider.of<ContactProvider>(context, listen: false);
      if (contactProvider.contacts.isEmpty) {
        contactProvider.loadContacts();
      }
    });
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  void _toggleMember(String memberId) {
    setState(() {
      if (_selectedMembers.contains(memberId)) {
        _selectedMembers.remove(memberId);
      } else {
        _selectedMembers.add(memberId);
      }
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个成员')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('正在创建群组...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final memberIds = _selectedMembers
          .map((id) => int.tryParse(id) ?? 0)
          .where((id) => id > 0)
          .toList();
      final groupNameInput = _groupNameController.text.trim();
      final group = await IMClient.instance.createGroup(
        name: groupNameInput,
        memberIds: memberIds,
      );
      final groupId = group.id.toString();
      final groupName = group.name.isNotEmpty ? group.name : groupNameInput;

      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('群组"$groupName"创建成功！'),
          backgroundColor: AppTheme.successColor));

      // 跳转到群聊页面（复用 ChatPage，isGroup=true）
      Navigator.pushReplacementNamed(
        context,
        AppRouter.chat,
        arguments: {
          'conversationId': groupId,
          'conversationName': groupName,
          'isGroup': true,
          'targetId': int.tryParse(groupId) ?? 0,
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群组'),
        actions: [
          TextButton(
            onPressed: _createGroup,
            child: const Text(
              '完成',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  labelText: '群名称',
                  hintText: '请输入群名称',
                  prefixIcon: const Icon(Icons.group_add),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入群名称';
                  }
                  return null;
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择成员 (${_selectedMembers.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<ContactProvider>(
                builder: (context, contactProvider, _) {
                  final contacts = contactProvider.contacts;
                  if (contacts.isEmpty && !contactProvider.isLoading) {
                    return const Center(
                      child: Text('暂无联系人，请先添加好友',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  if (contactProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final contactId = contact.id?.toString() ?? contact.imUserId?.toString() ?? '';
                      final displayName = contact.nickname?.isNotEmpty == true
                          ? contact.nickname!
                          : (contact.username?.isNotEmpty == true
                              ? contact.username!
                              : '未知用户');
                      final isSelected = _selectedMembers.contains(contactId);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) => _toggleMember(contactId),
                        title: Row(
                          children: [
                            AvatarWidget(name: displayName, size: 40),
                            const SizedBox(width: 12),
                            Text(displayName),
                          ],
                        ),
                        activeColor: AppTheme.primaryColor,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
