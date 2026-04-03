import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/audience_score.dart';
import '../models/creator_intelligence_report.dart';
import '../models/creator_survey.dart';
import '../models/feedback_entry.dart';
import 'demo_feedback_generator.dart';
import '../models/feedback_link.dart';
import '../models/user_profile.dart';

const _usersCol = 'users';
const _linksCol = 'links';
const _feedbacksCol = 'feedbacks';
const _audienceScoreSnapshotsSub = 'audienceScoreSnapshots';
/// Büyük creator JSON’u ana dökümandan ayırır (Web SDK dinleyici / belge boyutu).
const _audienceReportBodySub = 'reportBody';
const _audienceReportBodyDocId = 'full';
final _uuid = const Uuid();

// Rapor/AI: Gelen yorum sayısına göre rapor kapsamı artacak (az yorum → kısa özet,
// çok yorum → daha uzun, tema/yüzdeli, madde madde detaylı analiz).

class FirestoreService {
  FirestoreService() : _db = FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(_usersCol);
  CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection(_linksCol);
  CollectionReference<Map<String, dynamic>> get _feedbacks =>
      _db.collection(_feedbacksCol);

  // ----- Kullanıcı -----
  Future<void> setUserProfile(String uid, UserProfile profile) async {
    await _users.doc(uid).set(profile.toMap(), SetOptions(merge: true));
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final snap = await _users.doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return UserProfile.fromMap(uid, snap.data());
  }

  Stream<UserProfile?> userProfileStream(String uid) {
    return _users.doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return UserProfile.fromMap(uid, snap.data());
    });
  }

  // ----- Linkler (kısa kod: 8 karakter) -----
  String _shortCode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 8);
  }

  Future<FeedbackLink?> createLink(String ownerId, {String? title}) async {
    final code = _shortCode();
    final id = _links.doc().id;
    final link = FeedbackLink(
      id: id,
      ownerId: ownerId,
      code: code,
      title: title,
      createdAt: DateTime.now(),
      isActive: true,
    );
    await _links.doc(id).set(link.toMap());
    return link;
  }

  Future<FeedbackLink?> getLinkByCode(String code) async {
    final q = await _links
        .where('code', isEqualTo: code)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    return FeedbackLink.fromMap(doc.id, doc.data());
  }

  Stream<List<FeedbackLink>> linksForOwnerStream(String ownerId) {
    return _links
        .where('ownerId', isEqualTo: ownerId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => FeedbackLink.fromMap(d.id, d.data())).toList();
      list.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  Future<List<FeedbackLink>> getLinksForOwner(String ownerId) async {
    final snap = await _links
        .where('ownerId', isEqualTo: ownerId)
        .where('isActive', isEqualTo: true)
        .get();
    final list =
        snap.docs.map((d) => FeedbackLink.fromMap(d.id, d.data())).toList();
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  /// Linki pasifleştirir (sil); `getLinkByCode` ile bulunmaz, listelerden düşer.
  Future<void> deactivateLink(String linkId) async {
    await _links.doc(linkId).update({'isActive': false});
  }

  /// Bu linke gelen son yorumun tarihi (yorum yoksa null).
  Future<DateTime?> lastFeedbackAtForLink(String linkId) async {
    final q = await _feedbacks
        .where('linkId', isEqualTo: linkId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return FeedbackEntry.fromMap(q.docs.first.id, q.docs.first.data()).createdAt;
  }

  // ----- Feedback gönderme -----
  Future<void> addFeedback({
    required String linkId,
    String? responderName,
    String? relation,
    int? mood,
    required String textRaw,
    CreatorSurveyPayload? creatorSurvey,
  }) async {
    final id = _feedbacks.doc().id;
    final entry = FeedbackEntry(
      id: id,
      linkId: linkId,
      responderName: responderName?.trim().isEmpty == true ? null : responderName,
      relation: relation?.trim().isEmpty == true ? null : relation,
      mood: mood,
      textRaw: textRaw.trim(),
      createdAt: DateTime.now(),
      creatorSurvey:
          creatorSurvey != null && !creatorSurvey.isEffectivelyEmpty ? creatorSurvey : null,
    );
    await _feedbacks.doc(id).set(entry.toMap());
  }

  Stream<List<FeedbackEntry>> feedbacksForLinkStream(String linkId) {
    return _feedbacks
        .where('linkId', isEqualTo: linkId)
        .snapshots()
        .map((snap) {
      final entries =
          snap.docs.map((d) => FeedbackEntry.fromMap(d.id, d.data())).toList();
      entries.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return entries;
    });
  }

  Future<int> feedbackCountForLink(String linkId) async {
    final snap = await _feedbacks.where('linkId', isEqualTo: linkId).count().get();
    return snap.count ?? 0;
  }

  Future<List<FeedbackEntry>> getFeedbacksForLink(String linkId) async {
    final snap = await _feedbacks.where('linkId', isEqualTo: linkId).get();
    final entries = snap.docs
        .map((d) => FeedbackEntry.fromMap(d.id, d.data()))
        .toList();
    entries.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return entries;
  }

  /// Tüm aktif linklerdeki toplam yorum sayısı (havuz başlığı için).
  Future<int> countAllFeedbacksForOwner(String ownerId) async {
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return 0;
    var total = 0;
    for (final l in links) {
      total += await feedbackCountForLink(l.id);
    }
    return total;
  }

  /// Havuz: [getLinksForOwner] sırası **en yeni link önce**. Önceki hata:
  /// limit'i link sayısına bölüp her linkten az doküman alıyorduk; çok link varken
  /// binlerce yorum tek linkte olsa bile listede ~10–30 satır görünüyordu.
  Future<List<FeedbackEntry>> getFeedbackPoolForOwner(
    String ownerId, {
    int limit = 200,
  }) async {
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return <FeedbackEntry>[];

    final all = <FeedbackEntry>[];
    for (final link in links) {
      if (all.length >= limit) break;
      final need = limit - all.length;
      final snap = await _feedbacks
          .where('linkId', isEqualTo: link.id)
          .limit(need)
          .get();
      all.addAll(snap.docs.map((d) => FeedbackEntry.fromMap(d.id, d.data())));
    }

    all.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    if (all.length > limit) {
      return all.take(limit).toList();
    }
    return all;
  }

  /// Rapor için: aktif tüm linklerdeki **bütün** yorumları çeker (limit yok).
  /// [linkId + documentId] ile sayfalama — tek seferde binlerce doküman desteklenir.
  Future<List<FeedbackEntry>> getAllFeedbacksForOwner(String ownerId) async {
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return <FeedbackEntry>[];

    final all = <FeedbackEntry>[];
    const pageSize = 500;

    for (final link in links) {
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        Query<Map<String, dynamic>> q = _feedbacks
            .where('linkId', isEqualTo: link.id)
            .orderBy(FieldPath.documentId)
            .limit(pageSize);
        if (cursor != null) {
          q = q.startAfterDocument(cursor!);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        all.addAll(
          snap.docs.map((d) => FeedbackEntry.fromMap(d.id, d.data())),
        );
        if (snap.docs.length < pageSize) break;
        cursor = snap.docs.last;
      }
    }

    all.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return all;
  }

  /// Takipçi analizi tamamlandığında puan + kapak metrikleri + tam Creator raporu (geçmiş / gelişim).
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
    final payload = <String, dynamic>{
      'createdAt': FieldValue.serverTimestamp(),
      'overallScore': scores.overall,
      'positiveMomentum': scores.positiveMomentum,
      'riskControl': scores.riskControl,
      'dataDepth': scores.dataDepth,
      'feedbackCount': feedbackCount,
      'positiveCount': positiveCount,
      'neutralCount': neutralCount,
      'negativeCount': negativeCount,
    };
    if (communityPerception != null) {
      payload['communityPerception'] = communityPerception.clamp(0, 100);
    }
    if (trust != null) payload['trust'] = trust.clamp(0, 100);
    if (contentClarity != null) {
      payload['contentClarity'] = contentClarity.clamp(0, 100);
    }
    final summary = executiveSummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      payload['executiveSummary'] = summary;
    }
    // creatorReport ana dökümanda tutulmaz; reportBody/full altında saklanır (web dinleyici + 1 MiB limit).
    final ref =
        _users.doc(ownerId).collection(_audienceScoreSnapshotsSub).doc();
    final batch = _db.batch();
    batch.set(ref, payload);
    if (creatorReport != null) {
      batch.set(
        ref.collection(_audienceReportBodySub).doc(_audienceReportBodyDocId),
        <String, dynamic>{'creatorReport': creatorReport.toJson()},
      );
    }
    await batch.commit();
  }

  /// Liste akışında gövde yok; tam rapor için (detay ekranı).
  Future<AudienceScoreSnapshot?> loadAudienceScoreSnapshotWithBody(
    String ownerId,
    String snapshotId,
  ) async {
    final ref = _users.doc(ownerId).collection(_audienceScoreSnapshotsSub).doc(snapshotId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return null;
    var snap = AudienceScoreSnapshot.fromFirestore(doc.id, doc.data()!);
    if (snap.creatorReport != null) return snap;
    final bodyDoc =
        await ref.collection(_audienceReportBodySub).doc(_audienceReportBodyDocId).get();
    if (!bodyDoc.exists || bodyDoc.data() == null) return snap;
    final crRaw = bodyDoc.data()!['creatorReport'];
    if (crRaw is! Map) return snap;
    try {
      final cr = CreatorIntelligenceReport.fromJson(
        Map<String, dynamic>.from(crRaw),
      );
      return snap.copyWith(creatorReport: cr);
    } catch (_) {
      return snap;
    }
  }

  /// En yeni kayıt önce; grafik için son N analiz.
  Stream<List<AudienceScoreSnapshot>> audienceScoreHistoryStream(
    String ownerId, {
    int limit = 36,
  }) {
    return _users
        .doc(ownerId)
        .collection(_audienceScoreSnapshotsSub)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => AudienceScoreSnapshot.fromFirestore(
                  d.id,
                  d.data(),
                  omitCreatorReport: true,
                ),
              )
              .toList(),
        );
  }

  /// Geliştirme / test: Tek tek yorum yazmadan analiz ekranlarını denemek için
  /// çeşitli örnek yorumları ilk aktif linke ekler. [kDebugMode] dışında çağrılmamalı.
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
      (
        text:
            'İçerik kalitesi genel olarak iyi; bazı videolarda ses dengesi zayıf, mikrofon veya kurgu iyileşirse süper olur.',
        mood: 0,
        relation: 'iş arkadaşı',
      ),
      (
        text:
            'Güven veriyorsun, dürüst paylaşımların takdir ediliyor. Etkileşim için soru sormanı da seviyorum.',
        mood: 1,
        relation: 'arkadaş',
      ),
      (
        text:
            'Düzenli yayın yapmıyorsun gibi; istikrar olursa topluluk daha çok bağlanır.',
        mood: -1,
        relation: 'takipçi',
      ),
      (
        text:
            'Işık ve kamera açısı çok daha iyi olmuş, montaj akıcı. Teknik olarak gelişim gözüküyor.',
        mood: 1,
        relation: 'arkadaş',
      ),
      (
        text:
            'Marka ile uyumlu bir çizgin var; hashtag ve paylaşım stratejisi netleşirse daha çok kişiye ulaşırsın.',
        mood: 0,
        relation: 'müşteri',
      ),
      (
        text:
            'Empati kurduğun anlar çok güçlü; bazen sorunları çok büyüttüğün hissiyatı oluşuyor, denge iyi olur.',
        mood: -1,
        relation: 'takipçi',
      ),
      (
        text:
            'Motivasyon veren içerikler üretiyorsun; negatif enerji taşıyan kısımları azaltırsan daha geniş kitle açılır.',
        mood: 0,
        relation: 'takipçi',
      ),
      (
        text:
            'Açık ve şeffaf iletişimin güven oluşturuyor. Kısa ve net cümlelerle devam etmeni öneririm.',
        mood: 1,
        relation: 'aile',
      ),
      (
        text:
            'Reels formatında akış çok iyi; story tarafında biraz daha sık görünmek etkileşimi artırabilir.',
        mood: 0,
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

  /// Test: Rastgele şablonlarla çok sayıda yorum üretir (Firestore batch, max 450/yazım).
  /// [count] üst sınırı aşmasın diye 5000 ile sınırlıdır.
  Future<int> seedBulkDemoFeedbacksForOwner(
    String ownerId, {
    int count = 1000,
    int? seed,
  }) async {
    final n = count.clamp(1, 5000);
    final links = await getLinksForOwner(ownerId);
    if (links.isEmpty) return 0;

    final linkId = links.first.id;
    final rnd = Random(seed ?? DateTime.now().millisecondsSinceEpoch);

    const maxPerBatch = 450;
    var written = 0;
    var index = 0;

    while (written < n) {
      final remaining = n - written;
      final chunk = remaining > maxPerBatch ? maxPerBatch : remaining;
      final batch = _db.batch();
      for (var i = 0; i < chunk; i++) {
        final docRef = _feedbacks.doc();
        final entry = buildSyntheticFeedback(
          docId: docRef.id,
          linkId: linkId,
          rnd: rnd,
          index: index++,
        );
        batch.set(docRef, entry.toMap());
      }
      await batch.commit();
      written += chunk;
    }
    return written;
  }
}
