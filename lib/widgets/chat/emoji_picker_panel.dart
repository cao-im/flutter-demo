import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

/// 表情选择面板 — 基于 emoji_picker_flutter
class EmojiPickerPanel extends StatelessWidget {
  /// 选择表情后的回调，返回 Unicode 字符串
  final void Function(String emoji) onEmojiSelected;

  const EmojiPickerPanel({
    super.key,
    required this.onEmojiSelected,
  });

  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
      onEmojiSelected: (Category? category, Emoji emoji) {
        onEmojiSelected(emoji.emoji);
      },
      config: Config(
        height: 260,
        checkPlatformCompatibility: true,
        emojiViewConfig: const EmojiViewConfig(
          // 缩小图标，增加列数让布局更舒展
          columns: 10,
          emojiSizeMax: 24,
          verticalSpacing: 2,
          horizontalSpacing: 2,
          gridPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          backgroundColor: Colors.transparent,
          buttonMode: ButtonMode.MATERIAL,
        ),
        skinToneConfig: const SkinToneConfig(
          enabled: false,
          dialogBackgroundColor: Colors.white,
          indicatorColor: Colors.grey,
        ),
        categoryViewConfig: const CategoryViewConfig(
          initCategory: Category.SMILEYS,
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFF4A90D9),
          iconColorSelected: Color(0xFF4A90D9),
          iconColor: Color(0xFFBDBDBD),
        ),
        bottomActionBarConfig: const BottomActionBarConfig(
          enabled: false,
          showSearchViewButton: true,
          buttonColor: Color(0xFF4A90D9),
        ),
        searchViewConfig: const SearchViewConfig(
          backgroundColor: Colors.white,
          hintText: '搜索表情...',
        ),
      ),
    );
  }
}
