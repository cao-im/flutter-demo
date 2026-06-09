import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../providers/contact_provider.dart';
import '../services/api_service.dart';
import '../widgets/avatar_widget.dart';
import '../theme/app_theme.dart';

class DesktopGroupCreateDialog extends StatefulWidget {
  const DesktopGroupCreateDialog({super.key});

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DesktopGroupCreateDialog(),
    );
  }

  @override
  State<DesktopGroupCreateDialog> createState() => _DesktopGroupCreateDialogState();
}

class _DesktopGroupCreateDialogState extends State<DesktopGroupCreateDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // 确保联系人数据已加载（loadContacts 会正确管理 isLoading 状态）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ContactProvider>(context, listen: false).loadContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  void _toggleMember(String memberId) {
    setState(() {
      if (_selectedMemberIds.contains(memberId)) {
        _selectedMemberIds.remove(memberId);
      } else {
        _selectedMemberIds.add(memberId);
      }
    });
  }

  void _removeMember(String memberId) {
    setState(() => _selectedMemberIds.remove(memberId));
  }

  List<UserModel> _filterContacts(List<UserModel> contacts) {
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) return contacts;
    return contacts.where((c) {
      final name = c.nickname.isNotEmpty ? c.nickname : c.username;
      return name.toLowerCase().contains(keyword) || c.username.toLowerCase().contains(keyword);
    }).toList();
  }

  bool get _canCreate => _selectedMemberIds.isNotEmpty && _groupNameController.text.trim().isNotEmpty;

  Future<void> _createGroup() async {
    if (!_canCreate || _isCreating) return;

    setState(() => _isCreating = true);

    try {
      final storage = await SharedPreferences.getInstance();
      final userIdStr = storage.getString('im_user_id');
      final ownerId = int.tryParse(userIdStr ?? '');
      if (ownerId == null || ownerId <= 0) {
        throw Exception('无法获取当前用户 ID');
      }

      final memberIds = _selectedMemberIds.map((id) => int.tryParse(id) ?? 0).where((id) => id > 0).toList();
      final groupName = _groupNameController.text.trim();

      final apiService = ApiService();
      final result = await apiService.groupApi.createGroup(ownerId, groupName, memberIds);

      // 从 Result 包裹中提取 data 字段
      final groupData = result['data'] as Map<String, dynamic>? ?? result;

      if (!mounted) return;
      Navigator.of(context).pop({
        'groupId': groupData['id']?.toString(),
        'groupName': groupName,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('创建群组失败: $e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = (screenHeight * 0.8).clamp(0.0, 600.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 680,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppTheme.surfaceColor,
        ),
        child: Column(
          children: [
            _buildHeader(),
            Divider(height: 1, color: AppTheme.dividerColor),
            Expanded(child: _buildBody()),
            Divider(height: 1, color: AppTheme.dividerColor),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '发起群聊',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: Colors.grey[500]),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<ContactProvider>(
      builder: (context, contactProvider, _) {
        final allContacts = contactProvider.contacts;
        final filteredContacts = _filterContacts(allContacts);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：好友列表（60%）
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  _buildSearchBar(),
                  Divider(height: 1, color: AppTheme.dividerColor),
                  Expanded(child: _buildFriendList(filteredContacts, contactProvider.isLoading)),
                ],
              ),
            ),

            VerticalDivider(width: 1, color: AppTheme.dividerColor),

            // 右侧：已选成员预览（40%）
            Expanded(
              flex: 4,
              child: _buildSelectedPanel(allContacts),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 14),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '搜索好友...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 18, color: Colors.grey[500]),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildFriendList(List<UserModel> contacts, bool isLoading) {
    if (isLoading && contacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(_searchController.text.isNotEmpty ? '无匹配的好友' : '暂无好友', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: Colors.grey.shade100),
      itemBuilder: (ctx, index) => _buildFriendItem(contacts[index]),
    );
  }

  Widget _buildFriendItem(UserModel contact) {
    final displayName = contact.nickname.isNotEmpty ? contact.nickname : contact.username;
    final isSelected = _selectedMemberIds.contains(contact.id);

    return InkWell(
      onTap: () => _toggleMember(contact.id),
      hoverColor: AppTheme.primaryColor.withOpacity(0.04),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleMember(contact.id),
              activeColor: AppTheme.primaryColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            AvatarWidget(imageUrl: contact.avatar, name: displayName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimaryColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPanel(List<UserModel> allContacts) {
    final selectedContacts = allContacts.where((c) => _selectedMemberIds.contains(c.id)).toList();

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  '已选成员 (${_selectedMemberIds.length})',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.dividerColor),
          Expanded(
            child: selectedContacts.isEmpty
                ? Center(
                    child: Text(
                      '请从左侧选择好友',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedContacts.map((contact) => _buildSelectedChip(contact)).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedChip(UserModel contact) {
    final displayName = contact.nickname.isNotEmpty ? contact.nickname : contact.username;

    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWidget(imageUrl: contact.avatar, name: displayName, size: 28),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _removeMember(contact.id),
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Text(
            '群名称:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textSecondaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _groupNameController,
                style: const TextStyle(fontSize: 14),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '输入群名称',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600], padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8)),
            child: const Text('取消', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _canCreate && !_isCreating ? _createGroup : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            ),
            child: _isCreating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('创建', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
