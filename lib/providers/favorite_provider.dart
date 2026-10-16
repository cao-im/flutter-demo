import 'package:flutter/foundation.dart';

import '../models/favorite_item.dart';
import '../services/apis/favorite_api.dart';

class FavoriteProvider extends ChangeNotifier {
  final FavoriteApi _api = FavoriteApi();

  List<FavoriteItem> items = [];
  FavoriteItem? selected;
  var loading = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final rows = await _api.list();
      items = rows.map(FavoriteItem.fromJson).where((item) => item.id > 0).toList();
      if (selected != null && items.every((item) => item.id != selected!.id)) {
        selected = null;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> add(int mid) async {
    final row = await _api.add(mid);
    final item = FavoriteItem.fromJson(row);
    if (item.id <= 0) return;
    items = [item, ...items.where((existing) => existing.id != item.id)];
    notifyListeners();
  }

  Future<void> remove(int id) async {
    await _api.remove(id);
    items = items.where((item) => item.id != id).toList();
    if (selected?.id == id) selected = null;
    notifyListeners();
  }

  void select(FavoriteItem? item) {
    selected = item;
    notifyListeners();
  }
}
