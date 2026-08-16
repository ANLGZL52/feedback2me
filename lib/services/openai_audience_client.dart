import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/creator_intelligence_report.dart';
import '../models/feedback_entry.dart';

/// Sunucu-yetkili AI özet köprüsü istemcisi.
///
/// P0 güvenlik: OpenAI anahtarı ARTIK istemcide YOK. Bu sınıf sağlayıcıya
/// doğrudan HTTP çağrısı yapmaz; bunun yerine Firebase Auth ile doğrulanan `aiSummary`
/// callable fonksiyonunu çağırır. Model, prompt, endpoint ve anahtar tamamen
/// sunucu tarafındadır (bkz. functions/src/ai-core.ts). İstemci yalnızca
/// geri bildirim içeriğini gönderir. Herhangi bir hata → null → heuristik yedek.
class OpenAiAudienceClient {
  OpenAiAudienceClient();

  static const int chunkSize = 90;

  // Fonksiyon bölgesi: functions/src/index.ts ile aynı olmalı (us-central1).
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// AI yalnızca doğrulanmış bir Firebase kullanıcısı varken çalışır (callable
  /// kimlik doğrulaması gerektirir). Aksi halde heuristik yedek kullanılır.
  bool get isConfigured => FirebaseAuth.instance.currentUser != null;

  /// aiSummary callable'ına güvenli çağrı. Başarıda modelin ham JSON metnini,
  /// aksi halde (unauthenticated / rate-limit / sağlayıcı hatası / ağ) null döner.
  Future<String?> _callAiSummary(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable(
        'aiSummary',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final res = await callable.call(payload);
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        final content = data['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
      return null;
    } on FirebaseFunctionsException catch (_) {
      // unauthenticated / resource-exhausted / unavailable / internal → yedek.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Bir parçadaki girişleri callable şemasına çevirir (sunucu bunları tarihsel
  /// `mood|ilişki|anket_json|metin` formatına birebir kodlar).
  List<Map<String, dynamic>> _itemsForChunk(List<FeedbackEntry> chunk) {
    return chunk.map((e) {
      final survey = (e.creatorSurvey != null && !e.creatorSurvey!.isEffectivelyEmpty)
          ? e.creatorSurvey!.toCompactJson()
          : '-';
      return <String, dynamic>{
        'mood': e.mood ?? 0,
        'relation': (e.relation ?? '-'),
        'survey': survey,
        'text': e.textRaw,
      };
    }).toList();
  }

  /// Ham yorumları parçalayıp her parça için kısa JSON özet biriktirir (birleştirme için).
  Future<String?> collectPartialsDigest(
    List<FeedbackEntry> entries, {
    void Function(int index1Based, int totalChunks)? onChunkProgress,
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured || entries.isEmpty) return null;

    final chunks = <List<FeedbackEntry>>[];
    for (var i = 0; i < entries.length; i += chunkSize) {
      chunks.add(entries.sublist(i, i + chunkSize > entries.length ? entries.length : i + chunkSize));
    }

    final lang = outputEnglishModel ? 'en' : 'tr';
    final buf = StringBuffer();
    for (var p = 0; p < chunks.length; p++) {
      onChunkProgress?.call(p + 1, chunks.length);
      final raw = await _callAiSummary({
        'operation': 'partial_digest',
        'lang': lang,
        'chunkIndex': p + 1,
        'chunkTotal': chunks.length,
        'items': _itemsForChunk(chunks[p]),
      });
      if (raw == null) return null;
      buf.writeln(
        outputEnglishModel
            ? '--- CHUNK ${p + 1} / ${chunks.length} ---'
            : '--- PARÇA ${p + 1} / ${chunks.length} ---',
      );
      buf.writeln(raw);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return buf.toString();
  }

  /// Heuristik rapor JSON'unu premium danışman dilinde yeniden yazar; sayıları şema korur.
  Future<CreatorIntelligenceReport?> refineCreatorIntelligence(
    CreatorIntelligenceReport heuristic, {
    String? partialsDigest,
    String? surveyAggregateBlock,
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured) return null;

    final raw = await _callAiSummary({
      'operation': 'refine_report',
      'lang': outputEnglishModel ? 'en' : 'tr',
      'heuristic': heuristic.toJson(),
      'partialsDigest': ?partialsDigest,
      'surveyAggregate': ?surveyAggregateBlock,
    });
    if (raw == null) return null;
    final map = _parseJsonObject(raw);
    if (map == null) return null;
    try {
      return CreatorIntelligenceReport.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      final fence = s.lastIndexOf('```');
      if (fence != -1) s = s.substring(0, fence);
    }
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
