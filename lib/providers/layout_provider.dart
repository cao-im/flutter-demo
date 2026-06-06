import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class LayoutProvider with ChangeNotifier {
  int _selectedIndex = 0;
  String? _currentConversationId;
  String? _currentConversationName;
  bool _isGroup = false;
  UserModel? _selectedContact;

  int get selectedIndex => _selectedIndex;
  String? get currentConversationId => _currentConversationId;
  String? get currentConversationName => _currentConversationName;
  bool get isGroup => _isGroup;
  UserModel? get selectedContact => _selectedContact;

  void selectNavigation(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    // 切换到非通讯录标签时清除选中联系人
    if (index != 1) {
      _selectedContact = null;
    }
    debugPrint('📍[LayoutProvider] 切换导航项: $index');
    notifyListeners();
  }

  void selectConversation(String id, String name, bool isGroup) {
    if (_currentConversationId == id) {
      // 再次点击同一会话时，关闭右侧聊天面板
      clearConversation();
      return;
    }
    _currentConversationId = id;
    _currentConversationName = name;
    _isGroup = isGroup;
    debugPrint('📍[LayoutProvider] 选中会话: $id ($name, 群聊: $isGroup)');
    notifyListeners();
  }

  void clearConversation() {
    _currentConversationId = null;
    _currentConversationName = null;
    _isGroup = false;
    debugPrint('📍[LayoutProvider] 清除选中会话');
    notifyListeners();
  }

  /// 选中联系人（通讯录页面右侧详情展示）
  void selectContact(UserModel contact) {
    if (_selectedContact?.id == contact.id) return;
    _selectedContact = contact;
    debugPrint('📍[LayoutProvider] 选中联系人: ${contact.nickname} (${contact.id})');
    notifyListeners();
  }

  /// 清除选中联系人
  void clearSelectedContact() {
    _selectedContact = null;
    debugPrint('📍[LayoutProvider] 清除选中联系人');
    notifyListeners();
  }
}
