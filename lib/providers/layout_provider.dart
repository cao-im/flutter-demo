import 'package:flutter/foundation.dart';

class LayoutProvider with ChangeNotifier {
  int _selectedIndex = 0;
  String? _currentConversationId;
  String? _currentConversationName;
  bool _isGroup = false;

  int get selectedIndex => _selectedIndex;
  String? get currentConversationId => _currentConversationId;
  String? get currentConversationName => _currentConversationName;
  bool get isGroup => _isGroup;

  void selectNavigation(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    debugPrint('📍[LayoutProvider] 切换导航项: $index');
    notifyListeners();
  }

  void selectConversation(String id, String name, bool isGroup) {
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
}
