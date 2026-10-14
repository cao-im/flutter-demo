import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/contact_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';

/// 查看对方资料。打开时向服务器拉取最新昵称和头像。
class UserProfilePage extends StatefulWidget {
  final UserModel contact;

  const UserProfilePage({super.key, required this.contact});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late UserModel _contact;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final imUserId = int.tryParse(_contact.imUserId ?? '') ??
        int.tryParse(_contact.id) ??
        0;
    if (imUserId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final updated = await context.read<ContactProvider>().refreshContactFromServer(imUserId);
    if (!mounted) return;
    setState(() {
      if (updated != null) _contact = updated;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _contact.nickname.isNotEmpty ? _contact.nickname : _contact.username;
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        children: [
          Center(
            child: AvatarWidget(
              imageUrl: _contact.avatar,
              name: name.isNotEmpty ? name : '用户',
              size: 88,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              name.isNotEmpty ? name : '用户',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          if (_contact.username.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                '用户名 ${_contact.username}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor),
              ),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ],
        ],
      ),
    );
  }
}
