import 'package:drift/drift.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' hide Value;
import 'package:cao_im_sdk_flutter/storage/drift/app_database.dart';
import 'package:cao_im_sdk_flutter/storage/drift/tables/contacts_table.dart';
import '../models/user_model.dart';
import '../models/contact_info_model.dart';

class ContactDatabaseService {
  static final ContactDatabaseService _instance = ContactDatabaseService._internal();
  factory ContactDatabaseService() => _instance;
  ContactDatabaseService._internal();

  AppDatabase? _db;
  bool _isInitialized = false;

  Future<void> init({required int userId}) async {
    if (_isInitialized) return;

    try {
      _db = AppDatabase(userId);
      _isInitialized = true;
      print('[ContactDatabaseService] ✅ 初始化完成 (userId=$userId)');
    } catch (e, stackTrace) {
      print('[ContactDatabaseService] ❌ 初始化失败: $e');
      print('[ContactDatabaseService] 📍 堆栈: $stackTrace');
      rethrow;
    }
  }

  AppDatabase get database {
    if (_db == null || !_isInitialized) {
      throw StateError('ContactDatabaseService 未初始化，请先调用 init()');
    }
    return _db!;
  }

  /// 批量插入或更新联系人
  /// 核心规则：id字段为本地自增ID（由SQLite AUTOINCREMENT 自动分配，无业务含义）
  /// userId为业务键（存服务端 contactUserId，真正的联系人标识）
  /// upsert逻辑：先按userId查是否存在 → 存在则更新 | 不存在则插入（id自动分配）
  Future<void> upsertContacts(List<UserModel> users) async {
    if (users.isEmpty) return;

    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final user in users) {
      // 解析真正的用户ID（优先使用 imUserId，即服务端 contactUserId）
      final imUserId = int.tryParse(user.imUserId ?? '') ?? int.tryParse(user.id) ?? 0;
      if (imUserId <= 0) continue;

      // 按业务键 userId 查询是否已存在
      final existing = await (db.select(db.contacts)
            ..where((tbl) => tbl.userId.equals(imUserId)))
          .getSingleOrNull();

      final baseCompanion = ContactsCompanion(
        // id 由 SQLite AUTOINCREMENT 自动分配，不手动指定
        userId: Value(imUserId),
        username: Value(user.username),
        nickname: Value(user.nickname),
        avatar: Value(user.avatar ?? ''),
        location: const Value(''),
        remark: const Value(''),
        phone: Value(user.phone ?? ''),
        email: Value(user.email ?? ''),
        onlineStatus: Value(user.isOnline ? 1 : 0),
        status: Value(user.friendStatus),
        createTime: Value(user.createdAt != null ? (user.createdAt!.millisecondsSinceEpoch ~/ 1000) : now),
      );

      if (existing != null) {
        // 已存在 → 用本地 id 更新（id 不变，只更新业务字段）
        await (db.update(db.contacts)..where((tbl) => tbl.id.equals(existing.id)))
            .write(baseCompanion);
      } else {
        // 不存在 → 直接插入，id 由数据库 AUTOINCREMENT 自动分配
        await db.into(db.contacts).insert(baseCompanion);
      }
    }

    print('[ContactDatabaseService] ✅ 批量upsert完成: ${users.length} 个联系人');
  }

  Future<List<UserModel>> getAllContacts() async {
    final db = database;

    final rows = await (db.select(db.contacts)
          ..orderBy([(t) => OrderingTerm.asc(t.nickname)]))
        .get();

    return rows.map((row) => _toUserModel(row)).toList();
  }

  Future<List<UserModel>> getContactsByStatus(int friendStatus) async {
    final db = database;

    final rows = await (db.select(db.contacts)
          ..where((tbl) => tbl.status.equals(friendStatus))
          ..orderBy([(t) => OrderingTerm.asc(t.nickname)]))
        .get();

    return rows.map((row) => _toUserModel(row)).toList();
  }

  /// 根据 userId（真正的用户ID）查询联系人
  Future<UserModel?> getContactByUserId(int userId) async {
    final db = database;
    if (userId <= 0) return null;

    final row = await (db.select(db.contacts)
          ..where((tbl) => tbl.userId.equals(userId)))
        .getSingleOrNull();

    if (row == null) return null;
    return _toUserModel(row);
  }

  /// 批量根据 userId 列表查询联系人，返回 Map<userId, ContactInfo>
  Future<Map<int, ContactInfo>> getContactsByIds(List<int> ids) async {
    if (ids.isEmpty) {
      print('[ContactDatabaseService] ℹ️ getContactsByIds: 传入空列表，返回空Map');
      return {};
    }

    final db = database;

    try {
      final validIds = ids.where((id) => id > 0).toList();
      if (validIds.isEmpty) {
        print('[ContactDatabaseService] ⚠️ getContactsByIds: 所有ID均无效');
        return {};
      }

      print('[ContactDatabaseService] 🔍 getContactsByIds: 开始批量查询 ${validIds.length} 个联系人 (使用userId字段)');

      final query = db.select(db.contacts)
        ..where((tbl) => tbl.userId.isIn(validIds));

      final rows = await query.get();

      final result = <int, ContactInfo>{};
      for (final row in rows) {
        if (row.userId != null && row.userId! > 0) {
          result[row.userId!] = _toContactInfo(row);
        }
      }

      print('[ContactDatabaseService] ✅ getContactsByIds: 查询完成，找到 ${result.length}/${validIds.length} 个联系人');

      return result;
    } catch (e, stackTrace) {
      print('[ContactDatabaseService] ❌ getContactsByIds: 查询失败 - $e');
      print('[ContactDatabaseService] 📍 堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 根据 userId 删除联系人
  Future<void> deleteContactByUserId(int userId) async {
    final db = database;
    if (userId <= 0) {
      throw ArgumentError('无效的用户ID: $userId');
    }

    await (db.delete(db.contacts)..where((tbl) => tbl.userId.equals(userId))).go();

    print('[ContactDatabaseService] 🗑️ 联系人已删除: userId=$userId');
  }

  /// 兼容旧接口：根据字符串ID删除（自动识别为 userId）
  Future<void> deleteContact(String id) async {
    final userId = int.tryParse(id);
    if (userId == null || userId <= 0) {
      throw ArgumentError('无效的联系人ID: $id');
    }
    await deleteContactByUserId(userId);
  }

  Future<void> clearAllContacts() async {
    final db = database;

    await db.delete(db.contacts).go();

    print('[ContactDatabaseService] 🗑️ 所有联系人已清空');
  }

  Future<int> getContactsCount() async {
    final db = database;

    final count = await db.contacts.count().getSingle();

    return count;
  }

  /// 根据 userId 更新在线状态
  Future<void> updateContactOnlineStatus(int userId, bool isOnline) async {
    final db = database;
    if (userId <= 0) {
      throw ArgumentError('无效的用户ID: $userId');
    }

    await (db.update(db.contacts)
          ..where((tbl) => tbl.userId.equals(userId)))
        .write(ContactsCompanion(
              onlineStatus: Value(isOnline ? 1 : 0),
            ));

    print('[ContactDatabaseService] 📝 联系人在线状态已更新: userId=$userId, isOnline=$isOnline');
  }

  /// 兼容旧接口：字符串形式的在线状态更新
  Future<void> updateContactOnlineStatusString(String id, bool isOnline) async {
    final userId = int.tryParse(id) ?? 0;
    await updateContactOnlineStatus(userId, isOnline);
  }

  /// 根据 userId 更新昵称
  Future<void> updateContactNickname(int userId, String nickname) async {
    final db = database;
    if (userId <= 0) {
      throw ArgumentError('无效的用户ID: $userId');
    }

    await (db.update(db.contacts)
          ..where((tbl) => tbl.userId.equals(userId)))
        .write(ContactsCompanion(
              nickname: Value(nickname),
            ));

    print('[ContactDatabaseService] 📝 联系人昵称已更新: userId=$userId, nickname=$nickname');
  }

  /// 兼容旧接口：字符串形式的昵称更新
  Future<void> updateContactNicknameString(String id, String nickname) async {
    final userId = int.tryParse(id) ?? 0;
    await updateContactNickname(userId, nickname);
  }

  UserModel _toUserModel(Contact row) {
    // userId 是真正的用户ID（对应服务端 contactUserId），作为业务标识
    final realUserId = row.userId ?? 0;
    return UserModel(
      id: realUserId.toString(),       // id 使用真正的用户ID
      username: row.username,
      nickname: row.nickname,
      avatar: row.avatar.isNotEmpty ? row.avatar : null,
      email: row.email.isNotEmpty ? row.email : null,
      phone: row.phone.isNotEmpty ? row.phone : null,
      createdAt: row.createTime != null
          ? DateTime.fromMillisecondsSinceEpoch(row.createTime! * 1000)
          : null,
      isOnline: row.onlineStatus == 1,
      imUserId: realUserId.toString(), // imUserId 同样使用真正的用户ID
      friendStatus: row.status,
    );
  }

  ContactInfo _toContactInfo(Contact row) {
    return ContactInfo(
      id: row.id,                     // 本地自增ID（无业务含义）
      userId: row.userId ?? 0,        // 真正的用户ID（业务键）
      username: row.username,
      nickname: row.nickname,
      avatar: row.avatar,
      remark: row.remark,
    );
  }

  Future<void> close() async {
    if (_isInitialized && _db != null) {
      await _db!.close();
      _isInitialized = false;
      _db = null;
      print('[ContactDatabaseService] ✓ 连接已关闭');
    }
  }

  /// 重置单例状态（用于切换账号时调用）
  Future<void> reset() async {
    await close();
    print('[ContactDatabaseService] ✓ 单例已重置，可重新初始化');
  }
}
