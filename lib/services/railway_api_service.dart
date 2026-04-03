import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../models/audience_score.dart';
import '../models/creator_intelligence_report.dart';
import '../models/creator_survey.dart';
import '../models/feedback_entry.dart';
import '../models/feedback_link.dart';
import '../models/user_profile.dart';
import 'api_session.dart';
import 'app_data_backend.dart';

/// Railway üzerindeki Fastify + Prisma API.
class RailwayApiService implements AppDataBackend {
  String get _base => BackendConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (ApiSession.instance.accessToken != null)
          'Authorization': 'Bearer ${ApiSession.instance.accessToken}',
      };

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: _jsonHeaders);
    if (res.statusCode == 401) throw StateError('unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('GET $path → ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: _jsonHeaders,
      body: body == null ? null : jsonEncode(body),
    );
    if (res.statusCode == 401) throw StateError('unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('POST $path → ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _putJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final res = await http.put(
      Uri.parse('$_base$path'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode == 401) throw StateError('unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('PUT $path → ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _patch(String path) async {
    final res = await http.patch(
      Uri.parse('$_base$path'),
      headers: _jsonHeaders,
    );
    if (res.statusCode == 401) throw StateError('unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('PATCH $path → ${res.statusCode} ${res.body}');
    }
  }

  UserProfile? _parseUser(Map<String, dynamic>? u, String fallbackUid) {
    if (u == null) return null;
    return UserProfile(
      uid: u['uid'] as String? ?? fallbackUid,
      displayName: u['displayName'] as String?,
      email: u['email'] as String?,
      photoUrl: u['photoUrl'] as String?,
      handle: u['handle'] as String?,
      isPremium: u['isPremium'] == true,
      premiumUntil: u['premiumUntil'] != null
          ? DateTime.tryParse(u['premiumUntil'] as String)
          : null,
      createdAt: u['createdAt'] != null
          ? DateTime.tryParse(u['createdAt'] as String)
          : null,
    );
  }

  @override
  Future<void> setUserProfile(String uid, UserProfile profile) async {
    await _putJson('/me', body: profile.toMap());
  }

  @override
  Future<UserProfile?> getUserProfile(String uid) async {
    final j = await _getJson('/me');
    return _parseUser(j['user'] as Map<String, dynamic>?, uid);
  }

  @override
  Stream<UserProfile?> userProfileStream(String uid) async* {
    yield await getUserProfile(uid);
    yield* Stream.periodic(const Duration(seconds: 4), (_) => uid).asyncMap(
          (_) => getUserProfile(uid),
        );
  }

  @override
  Future<FeedbackLink?> createLink(String ownerId, {String? title}) async {
    final j = await _postJson(
      '/links',
      body: title != null ? {'title': title} : {},
    );
    final link = j['link'] as Map<String, dynamic>?;
    if (link == null) return null;
    return FeedbackLink.fromMap(link['id'] as String, link);
  }

  @override
  Future<FeedbackLink?> getLinkByCode(String code) async {
    final c = code.trim().toLowerCase();
    final res = await http.get(
      Uri.parse('$_base/public/links/by-code/$c'),
      headers: const {'Accept': 'application/json'},
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('public link → ${res.statusCode} ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final link = j['link'] as Map<String, dynamic>?;
    if (link == null) return null;
    return FeedbackLink.fromMap(link['id'] as String, link);
  }

  @override
  Stream<List<FeedbackLink>> linksForOwnerStream(String ownerId) async* {
    yield await getLinksForOwner(ownerId);
    yield* Stream.periodic(const Duration(seconds: 4), (_) => ownerId).asyncMap(
          (_) => getLinksForOwner(ownerId),
        );
  }

  @override
  Future<List<FeedbackLink>> getLinksForOwner(String ownerId) async {
    final j = await _getJson('/links');
    final list = j['links'] as List<dynamic>? ?? [];
    return list
        .map((e) => FeedbackLink.fromMap(
              (e as Map)['id'] as String,
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  @override
  Future<void> deactivateLink(String linkId) async {
    await _patch('/links/$linkId/deactivate');
  }

  @override
  Future<DateTime?> lastFeedbackAtForLink(String linkId) async {
    final j = await _getJson('/links/$linkId/feedbacks/last-at');
    final raw = j['lastFeedbackAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw as String);
  }

  @override
  Future<void> addFeedback({
    required String linkId,
    String? responderName,
    String? relation,
    int? mood,
    required String textRaw,
    CreatorSurveyPayload? creatorSurvey,
  }) async {
    final body = <String, dynamic>{
      'linkId': linkId,
      'textRaw': textRaw,
      if (mood != null) 'mood': mood,
      if (relation != null) 'relation': relation,
      if (responderName != null) 'responderName': responderName,
      if (creatorSurvey != null && !creatorSurvey.isEffectivelyEmpty)
        'creatorSurvey': creatorSurvey.toMap(),
    };
    await _postJson('/feedbacks', body: body);
  }

  @override
  Stream<List<FeedbackEntry>> feedbacksForLinkStream(String linkId) async* {
    yield await getFeedbacksForLink(linkId);
    yield* Stream.periodic(const Duration(seconds: 5), (_) => linkId).asyncMap(
          (_) => getFeedbacksForLink(linkId),
        );
  }

  @override
  Future<int> feedbackCountForLink(String linkId) async {
    final list = await getFeedbacksForLink(linkId);
    return list.length;
  }

  @override
  Future<List<FeedbackEntry>> getFeedbacksForLink(String linkId) async {
    final j = await _getJson('/links/$linkId/feedbacks');
    final list = j['feedbacks'] as List<dynamic>? ?? [];
    return list
        .map((e) => _feedbackFromApi(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  FeedbackEntry _feedbackFromApi(Map<String, dynamic> e) {
    return FeedbackEntry.fromMap(
      e['id'] as String? ?? '',
      e,
    );
  }

  @override
  Future<int> countAllFeedbacksForOwner(String ownerId) async {
    final links = await getLinksForOwner(ownerId);
    var n = 0;
    for (final l in links) {
      n += await feedbackCountForLink(l.id);
    }
    return n;
  }

  @override
  Future<List<FeedbackEntry>> getFeedbackPoolForOwner(
    String ownerId, {
    int limit = 200,
  }) async {
    final j = await _getJson('/me/feedback-pool?limit=$limit');
    final list = j['feedbacks'] as List<dynamic>? ?? [];
    return list
        .map((e) => _feedbackFromApi(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<FeedbackEntry>> getAllFeedbacksForOwner(String ownerId) async {
    final links = await getLinksForOwner(ownerId);
    final all = <FeedbackEntry>[];
    for (final l in links) {
      all.addAll(await getFeedbacksForLink(l.id));
    }
    all.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return all;
  }

  @override
  Future<void> saveAudienceScoreSnapshot({
    required String ownerId,
    required AudienceScoreBreakdown scores,
    required int feedbackCount,
    required int positiveCount,
    required int neutralCount,
    required int negativeCount,
    int? communityPerception,
    int? trust,
    int? contentClarity,
    String? executiveSummary,
    CreatorIntelligenceReport? creatorReport,
  }) async {
    final body = <String, dynamic>{
      'scores': {
        'overall': scores.overall,
        'positiveMomentum': scores.positiveMomentum,
        'riskControl': scores.riskControl,
        'dataDepth': scores.dataDepth,
      },
      'feedbackCount': feedbackCount,
      'positiveCount': positiveCount,
      'neutralCount': neutralCount,
      'negativeCount': negativeCount,
      if (communityPerception != null)
        'communityPerception': communityPerception.clamp(0, 100),
      if (trust != null) 'trust': trust.clamp(0, 100),
      if (contentClarity != null)
        'contentClarity': contentClarity.clamp(0, 100),
      if (executiveSummary != null && executiveSummary.trim().isNotEmpty)
        'executiveSummary': executiveSummary.trim(),
      if (creatorReport != null) 'creatorReport': creatorReport.toJson(),
    };
    await _postJson('/audience-snapshots', body: body);
  }

  @override
  Future<AudienceScoreSnapshot?> loadAudienceScoreSnapshotWithBody(
    String ownerId,
    String snapshotId,
  ) async {
    final j = await _getJson('/audience-snapshots/$snapshotId');
    final s = j['snapshot'] as Map<String, dynamic>?;
    if (s == null) return null;
    return AudienceScoreSnapshot.fromApiDetail(s);
  }

  @override
  Stream<List<AudienceScoreSnapshot>> audienceScoreHistoryStream(
    String ownerId, {
    int limit = 36,
  }) async* {
    yield await _fetchSnapshots(limit);
    yield* Stream.periodic(const Duration(seconds: 6), (_) => limit).asyncMap(
          (_) => _fetchSnapshots(limit),
        );
  }

  Future<List<AudienceScoreSnapshot>> _fetchSnapshots(int limit) async {
    final j = await _getJson('/audience-snapshots?limit=$limit');
    final list = j['snapshots'] as List<dynamic>? ?? [];
    return list
        .map(
          (e) => AudienceScoreSnapshot.fromApiLite(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  @override
  Future<int> seedDemoFeedbacksForOwner(String ownerId) async {
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return 0;
    final linkId = links.first.id;
    const samples = <({String text, int mood, String? relation})>[
      (
        text:
            'İçeriklerin çok faydalı, özellikle son videoda anlattığın konu bana ilham verdi. '
                'Takipçi olarak devamını bekliyorum.',
        mood: 1,
        relation: 'takipçi',
      ),
      (
        text:
            'Mesajların bazen karışık geliyor; daha net bir ana fikir ile başlarsan daha iyi anlaşılır.',
        mood: 0,
        relation: 'arkadaş',
      ),
      (
        text:
            'Samimi duruyorsun ama ara ara yapay hissedilen kısımlar var; daha doğal konuşma tonu iyi olur.',
        mood: -1,
        relation: 'takipçi',
      ),
    ];
    for (final s in samples) {
      await addFeedback(
        linkId: linkId,
        relation: s.relation,
        mood: s.mood,
        textRaw: s.text,
      );
    }
    return samples.length;
  }

  @override
  Future<int> seedBulkDemoFeedbacksForOwner(
    String ownerId, {
    int count = 1000,
    int? seed,
  }) async {
    final n = count.clamp(1, 500);
    var written = 0;
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return 0;
    final linkId = links.first.id;
    while (written < n) {
      await addFeedback(
        linkId: linkId,
        mood: written % 3 - 1,
        textRaw:
            'Örnek toplu yorum #$written (seed=${seed ?? 0}). '
            'Gerçek kullanımda bu mod Firestore batch ile daha hızlıdır.',
      );
      written++;
    }
    return written;
  }
}
