class BomCalculator {
  /// Index BOM: pos_menus_id → [{items_id, quantity}, ...]
  static Map<int, List<Map<String, dynamic>>> indexBom(List bom) {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final row in bom) {
      final menuId = (row['pos_menus_id'] as num).toInt();
      (map[menuId] ??= []).add({
        'items_id': (row['items_id'] as num).toInt(),
        'quantity': (row['quantity'] as num).toInt(),
      });
    }
    return map;
  }

  /// Kebutuhan material untuk SATU baris cart → {items_id: qty_nisik}.
  /// prop.quantity di cart sudah absolut (dikali paket saat dipilih) —
  /// JANGAN dikali quantity baris lagi.
  static Map<int, int> materialsForLine(
    Map<String, dynamic> line,
    Map<int, List<Map<String, dynamic>>> bomIndex,
  ) {
    final need = <int, int>{};
    final menuId = (line['pos_menus_id'] as num?)?.toInt();
    if (menuId == null) return need;
    final lineQty = (line['quantity'] as num?)?.toInt() ?? 1;

    for (final b in (bomIndex[menuId] ?? const [])) {
      need[b['items_id'] as int] =
          (need[b['items_id'] as int] ?? 0) + (b['quantity'] as int) * lineQty;
    }

    final props = (line['pos_cart_props'] as List?) ?? const [];
    for (final p in props) {
      final propMenuId = (p['pos_menus_id'] as num?)?.toInt();
      if (propMenuId == null) continue;
      final propQty = (p['quantity'] as num?)?.toInt() ?? 0;
      for (final b in (bomIndex[propMenuId] ?? const [])) {
        need[b['items_id'] as int] =
            (need[b['items_id'] as int] ?? 0) + (b['quantity'] as int) * propQty;
      }
    }
    return need;
  }

  /// Total kebutuhan seluruh cart → {items_id: qty_nisik}.
  static Map<int, int> totalNeed(
    List<Map<String, dynamic>> cart,
    Map<int, List<Map<String, dynamic>>> bomIndex,
  ) {
    final total = <int, int>{};
    for (final line in cart) {
      materialsForLine(line, bomIndex).forEach((id, qty) {
        total[id] = (total[id] ?? 0) + qty;
      });
    }
    return total;
  }
}
