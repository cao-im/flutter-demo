import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _imTokenKey = 'im_token';
  static const String _userIdKey = 'user_id';
  static const String _imUserIdKey = 'im_user_id';
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';
  static const String _autoLoginKey = 'auto_login';

  static Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  static Future<void> saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString(_tokenKey);
  }

  static Future<void> removeToken() async {
    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
  }

  static Future<void> saveImToken(String imToken) async {
    final prefs = await _prefs;
    await prefs.setString(_imTokenKey, imToken);
  }

  static Future<String?> getImToken() async {
    final prefs = await _prefs;
    return prefs.getString(_imTokenKey);
  }

  static Future<void> saveUserId(String userId) async {
    final prefs = await _prefs;
    await prefs.setString(_userIdKey, userId);
  }

  static Future<String?> getUserId() async {
    final prefs = await _prefs;
    return prefs.getString(_userIdKey);
  }

  static Future<void> saveImUserId(String imUserId) async {
    final prefs = await _prefs;
    await prefs.setString(_imUserIdKey, imUserId);
  }

  static Future<String?> getImUserId() async {
    final prefs = await _prefs;
    return prefs.getString(_imUserIdKey);
  }

  static Future<void> saveUsername(String username) async {
    final prefs = await _prefs;
    await prefs.setString(_usernameKey, username);
  }

  static Future<String?> getUsername() async {
    final prefs = await _prefs;
    return prefs.getString(_usernameKey);
  }

  static Future<void> savePassword(String password) async {
    final prefs = await _prefs;
    await prefs.setString(_passwordKey, password);
  }

  static Future<String?> getPassword() async {
    final prefs = await _prefs;
    return prefs.getString(_passwordKey);
  }

  static Future<void> removePassword() async {
    final prefs = await _prefs;
    await prefs.remove(_passwordKey);
  }

  static Future<void> setAutoLogin(bool autoLogin) async {
    final prefs = await _prefs;
    await prefs.setBool(_autoLoginKey, autoLogin);
  }

  static Future<bool> getAutoLogin() async {
    final prefs = await _prefs;
    return prefs.getBool(_autoLoginKey) ?? false;
  }

  static Future<void> clearAll() async {
    final prefs = await _prefs;
    await prefs.clear();
  }
}
