import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  List<String> _selectedMembers = [];

  final List<Map<String, dynamic>> _mockFriends = [
    {'id': '1', 'name': '张三', 'avatar': null},
    {'id': '2', 'name': '李四', 'avatar': null},
    {'id': '3', 'name': '王五', 'avatar': null},
    {'id': '4', 'name': '赵六', 'avatar': null},
    {'id': '5', 'name': '钱七', 'avatar': null},
  ];

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

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('群组"${_groupNameController.text}"创建成功！'),
        backgroundColor: AppTheme.successColor,
      ),
    );

    Navigator.pop(context);
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
              child: ListView.builder(
                itemCount: _mockFriends.length,
                itemBuilder: (context, index) {
                  final friend = _mockFriends[index];
                  final isSelected = _selectedMembers.contains(friend['id']);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (_) => _toggleMember(friend['id']),
                    title: Row(
                      children: [
                        AvatarWidget(name: friend['name'], size: 40),
                        const SizedBox(width: 12),
                        Text(friend['name']),
                      ],
                    ),
                    activeColor: AppTheme.primaryColor,
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
