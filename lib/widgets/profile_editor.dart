import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/apis/file_api.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

/// 编辑自己的头像、昵称、邮箱和手机号。
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _seeded = false;
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedName;

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _seed(UserModel user) {
    if (_seeded) return;
    _nicknameController.text = user.nickname;
    _emailController.text = user.email ?? '';
    _phoneController.text = user.phone ?? '';
    _seeded = true;
  }

  Future<void> _pickAvatar() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedBytes = bytes;
        _pickedName = image.name;
      });
    } catch (e) {
      _showTip('选择头像失败');
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null || _saving) return;

    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (nickname.isEmpty || nickname.length > 20) {
      _showTip('昵称需为 1-20 个字');
      return;
    }
    if (email.isNotEmpty && !_looksLikeEmail(email)) {
      _showTip('邮箱格式不正确');
      return;
    }
    if (phone.isNotEmpty && !RegExp(r'^\+?[0-9]{6,20}$').hasMatch(phone)) {
      _showTip('手机号格式不正确');
      return;
    }

    final data = <String, dynamic>{};
    if (nickname != user.nickname) data['nickname'] = nickname;
    if (email != (user.email ?? '')) data['email'] = email;
    if (phone != (user.phone ?? '')) data['phone'] = phone;

    setState(() => _saving = true);
    try {
      final picked = _pickedBytes;
      if (picked != null) {
        final ext = _extensionOf(_pickedName ?? '');
        final url = await FileApi().uploadBytes(
          picked,
          'avatar_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        data['avatar'] = url;
      }
      if (data.isEmpty) {
        _showTip('没有需要保存的修改');
        return;
      }
      final ok = await auth.updateProfile(data);
      if (!mounted) return;
      if (!ok) {
        _showTip(auth.errorMessage ?? '保存失败');
        return;
      }
      final updated = auth.user;
      final imUserId = int.tryParse(updated?.imUserId ?? '') ?? 0;
      if (updated != null && imUserId > 0) {
        context.read<ChatProvider>().applySelfProfile(
              userId: imUserId,
              nickname: updated.nickname,
              avatar: updated.avatar ?? '',
            );
      }
      setState(() {
        _pickedBytes = null;
        _pickedName = null;
      });
      _showTip('资料已保存');
    } catch (e) {
      _showTip(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
    return allowed.contains(ext) ? ext : 'jpg';
  }

  void _showTip(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user != null && !_seeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _seeded) return;
        _seed(user);
        setState(() {});
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '编辑资料',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context)),
        ),
        const SizedBox(height: 6),
        Text(
          '用户名 ${user?.username ?? ''}',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
        ),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: _saving ? null : _pickAvatar,
            child: Stack(
              children: [
                _pickedBytes != null
                    ? ClipOval(
                        child: Image.memory(
                          _pickedBytes!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      )
                    : AvatarWidget(
                        imageUrl: user?.avatar,
                        name: user?.nickname ?? user?.username,
                        size: 88,
                      ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('点击更换头像', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
        ),
        const SizedBox(height: 24),
        _field(controller: _nicknameController, label: '昵称', maxLength: 20),
        const SizedBox(height: 16),
        _field(controller: _emailController, label: '邮箱', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        _field(controller: _phoneController, label: '手机号', keyboardType: TextInputType.phone),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中...' : '保存'),
          ),
        ),
      ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
      ),
    );
  }
}
