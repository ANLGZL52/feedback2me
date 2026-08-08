import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_feedback_summary.dart';

/// FeedbackToMe 2.0 — Topluluk özetinin cihaz-yerel önbelleği (link başına).
/// Süresi dolmuş link için özet bir kez üretilir, sonra buradan okunur; böylece
/// tekrar AI çağrısı yapılmaz (maliyet). Aktif linkler önbelleğe alınmaz.
class CommunitySummaryStore {
  CommunitySummaryStore._();
  static final CommunitySummaryStore instance = CommunitySummaryStore._();

  static const _prefix = 'community_summary_';

  Future<void> save(String linkId, CommunityFeedbackSummary summary) async {
    if (linkId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      '$_prefix$linkId',
      jsonEncode({'v': 1, 'summary': summary.toJson()}),
    );
  }

  Future<CommunityFeedbackSummary?> load(String linkId) async {
    if (linkId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$linkId');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final s = m['summary'];
      if (s is Map) {
        return CommunityFeedbackSummary.fromJson(Map<String, dynamic>.from(s));
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
