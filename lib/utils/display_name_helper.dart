import '../models/contact_info_model.dart';

class DisplayNameHelper {
  static String? getDisplayName(ContactInfo? contact) {
    if (contact == null) return null;
    
    if (contact.remark.isNotEmpty) {
      return contact.remark;
    }
    
    if (contact.nickname.isNotEmpty) {
      return contact.nickname;
    }
    
    if (contact.username.isNotEmpty) {
      return contact.username;
    }
    
    return null;
  }

  static String getDisplayNameOrDefault(ContactInfo? contact, int targetId) {
    final displayName = getDisplayName(contact);
    return displayName ?? '用户$targetId';
  }

  static String? getDisplayAvatar(ContactInfo? contact) {
    if (contact == null || contact.avatar.isEmpty) {
      return null;
    }
    return contact.avatar;
  }
}
