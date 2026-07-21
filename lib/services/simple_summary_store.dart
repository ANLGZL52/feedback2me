import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'report_service.dart';

/// Basit geri bildirim özetinin cihaz-yerel önbelleği (link başına).
/// Detaylı rapor geçmişinden (Firestore/Railway snapshot) tamamen ayrıdır;
/// süresi dolmuş link için özet bir kez üretilir, sonra buradan okunur.
class SimpleSummaryStore {
  SimpleSummaryStore._();
  static final SimpleSummaryStore instance = SimpleSummaryStore._();

  static const _prefix = 'simple_summary_';

  Future<void> save(String linkId, SimpleRequestSummary summary) async {
    if (linkId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      '$_prefix$linkId',
      jsonEncode({'v': 1, 'summary': summary.toJson()}),
    );
  }

  Future<SimpleRequestSummary?> load(String linkId) async {
    if (linkId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$linkId');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final s = m['summary'];
      if (s is Map) {
        return SimpleRequestSummary.fromJson(Map<String, dynamic>.from(s));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> has(String linkId) async {
    if (linkId.isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    return p.containsKey('$_prefix$linkId');
  }
}
