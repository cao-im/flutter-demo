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

  Future<void> upsertContacts(List<UserModel> users) async {
    if (users.isEmpty) return;

    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.batch((batch) {
      for (final user in users) {
        final contactId = int.tryParse(user.id) ?? int.tryParse(user.imUserId ?? '') ?? 0;
        if (contactId <= 0) continue;

        final companion = ContactsCompanion(
          id: Value(contactId),
          userId: Value(int.tryParse(user.imUserId ?? '') ?? int.tryParse(user.id) ?? 0),
          username: Value(user.username),
          nickname: Value(user.nickname),
          avatar: Value(user.avatar ?? ''),
          phone: Value(user.phone ?? ''),
          email: Value(user.email ?? ''),
          onlineStatus: Value(user.isOnline ? 1 : 0),
          status: Value(user.friendStatus),
          createTime: Value(user.createdAt != null ? (user.createdAt!.millisecondsSinceEpoch ~/ 1000) : now),
        );

        batch.insertAll(
          db.contacts,
          [companion],
          onConflict: DoUpdate((old) => companion),
        );
      }
    });

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

  Future<UserModel?> getContactById(String id) async {
    final db = database;
    final contactId = int.tryParse(id);
    if (contactId == null || contactId <= 0) return null;

    final row = await (db.select(db.contacts)
          ..where((tbl) => tbl.id.equals(contactId)))
        .getSingleOrNull();

    if (row == null) return null;
    return _toUserModel(row);
  }

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

  Future<void> deleteContact(String id) async {
    final db = database;
    final contactId = int.tryParse(id);
    if (contactId == null || contactId <= 0) {
      throw ArgumentError('无效的联系人ID: $id');
    }

    await (db.delete(db.contacts)..where((tbl) => tbl.id.equals(contactId))).go();

    print('[ContactDatabaseService] 🗑️ 联系人已删除: id=$id');
  }

  Future<void> deleteContactByImUserId(String imUserId) async {
    final db = database;
    final contactId = int.tryParse(imUserId);
    if (contactId == null || contactId <= 0) {
      throw ArgumentError('无效的IM用户ID: $imUserId');
    }

    await (db.delete(db.contacts)..where((tbl) => tbl.id.equals(contactId))).go();

    print('[ContactDatabaseService] 🗑️ 联系人已删除: imUserId=$imUserId');
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

  Future<void> updateContactOnlineStatus(String id, bool isOnline) async {
    final db = database;
    final contactId = int.tryParse(id);
    if (contactId == null || contactId <= 0) {
      throw ArgumentError('无效的联系人ID: $id');
    }

    await (db.update(db.contacts)
          ..where((tbl) => tbl.id.equals(contactId)))
        .write(ContactsCompanion(
              onlineStatus: Value(isOnline ? 1 : 0),
            ));

    print('[ContactDatabaseService] 📝 联系人在线状态已更新: id=$id, isOnline=$isOnline');
  }

  Future<void> updateContactNickname(String id, String nickname) async {
    final db = database;
    final contactId = int.tryParse(id);
    if (contactId == null || contactId <= 0) {
      throw ArgumentError('无效的联系人ID: $id');
    }

    await (db.update(db.contacts)
          ..where((tbl) => tbl.id.equals(contactId)))
        .write(ContactsCompanion(
              nickname: Value(nickname),
            ));

    print('[ContactDatabaseService] 📝 联系人昵称已更新: id=$id, nickname=$nickname');
  }

  UserModel _toUserModel(Contact row) {
    return UserModel(
      id: row.id.toString(),
      username: row.username,
      nickname: row.nickname,
      avatar: row.avatar.isNotEmpty ? row.avatar : null,
      email: row.email.isNotEmpty ? row.email : null,
      phone: row.phone.isNotEmpty ? row.phone : null,
      createdAt: row.createTime != null
          ? DateTime.fromMillisecondsSinceEpoch(row.createTime! * 1000)
          : null,
      isOnline: row.onlineStatus == 1,
      imUserId: row.id.toString(),
      friendStatus: row.status,
    );
  }

  ContactInfo _toContactInfo(Contact row) {
    return ContactInfo(
      id: row.id,
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
}
