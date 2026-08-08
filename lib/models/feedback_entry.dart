import 'package:cloud_firestore/cloud_firestore.dart';

import 'creator_survey.dart';

/// Bir linke yazılmış tek bir feedback (anonim olabilir).
class FeedbackEntry {
  FeedbackEntry({
    required this.id,
    required this.linkId,
    this.responderName,
    this.relation,
    this.mood,
    this.reaction,
    required this.textRaw,
    this.textClean,
    this.createdAt,
    this.creatorSurvey,
  });

  final String id;
  final String linkId;
  final String? responderName;
  final String? relation;
  final int? mood; // -1, 0, 1

  /// FeedbackToMe 2.0 reaction anahtarı (ör. "fire"). Eski kayıtlarda null;
  /// duygu [mood]'dan türetilir. Bkz. config/feedback_reactions.dart.
  final String? reaction;
  final String textRaw;
  final String? textClean;
  final DateTime? createdAt;

  /// İçerik üreticisi anketı (isteğe bağlı yapılandırılmış bağlam).
  final CreatorSurveyPayload? creatorSurvey;

  static DateTime? _parseCreatedAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  factory FeedbackEntry.fromMap(String id, Map<String, dynamic>? data) {
    if (data == null) return FeedbackEntry(id: id, linkId: '', textRaw: '');
    Map<String, dynamic>? surveyRaw;
    final rawSurvey = data['creatorSurvey'];
    if (rawSurvey is Map<String, dynamic>) {
      surveyRaw = rawSurvey;
    } else if (rawSurvey is Map) {
      surveyRaw = Map<String, dynamic>.from(rawSurvey);
    }

    return FeedbackEntry(
      id: id,
      linkId: data['linkId'] as String? ?? '',
      responderName: data['responderName'] as String?,
      relation: data['relation'] as String?,
      mood: data['mood'] as int?,
      reaction: data['reaction'] as String?,
      textRaw: data['textRaw'] as String? ?? '',
      textClean: data['textClean'] as String?,
      createdAt: _parseCreatedAt(data['createdAt']),
      creatorSurvey: surveyRaw != null && surveyRaw.isNotEmpty
          ? CreatorSurveyPayload.fromMap(surveyRaw)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'linkId': linkId,
      'responderName': responderName,
      'relation': relation,
      'mood': mood,
      if (reaction != null) 'reaction': reaction,
      'textRaw': textRaw,
      'textClean': textClean,
      'createdAt': createdAt?.toIso8601String(),
      if (creatorSurvey != null && !creatorSurvey!.isEffectivelyEmpty)
        'creatorSurvey': creatorSurvey!.toMap(),
    };
  }
}
