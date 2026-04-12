import '../models/audience_score.dart';
import '../models/creator_intelligence_report.dart';
import '../models/creator_survey.dart';
import '../models/feedback_entry.dart';
import '../models/feedback_link.dart';
import '../models/user_profile.dart';

/// Firestore veya Railway REST — uygulama tek arayüzden konuşur.
abstract class AppDataBackend {
  Future<void> setUserProfile(String uid, UserProfile profile);

  Future<UserProfile?> getUserProfile(String uid);

  Stream<UserProfile?> userProfileStream(String uid);

  Future<FeedbackLink?> createLink(String ownerId, {String? title});

  Future<FeedbackLink?> getLinkByCode(String code);

  Stream<List<FeedbackLink>> linksForOwnerStream(String ownerId);

  Future<List<FeedbackLink>> getLinksForOwner(String ownerId);

  Future<void> deactivateLink(String linkId);

  Future<DateTime?> lastFeedbackAtForLink(String linkId);

  Future<void> addFeedback({
    required String linkId,
    String? responderName,
    String? relation,
    int? mood,
    required String textRaw,
    CreatorSurveyPayload? creatorSurvey,
  });

  Stream<List<FeedbackEntry>> feedbacksForLinkStream(String linkId);

  Future<int> feedbackCountForLink(String linkId);

  Future<List<FeedbackEntry>> getFeedbacksForLink(String linkId);

  Future<int> countAllFeedbacksForOwner(String ownerId);

  Future<List<FeedbackEntry>> getFeedbackPoolForOwner(
    String ownerId, {
    int limit = 200,
  });

  Future<List<FeedbackEntry>> getAllFeedbacksForOwner(String ownerId);

  Future<void> saveAudienceScoreSnapshot({
    required String ownerId,
    required AudienceScoreBreakdown scores,
    required int feedbackCount,
    required int positiveCount,
    required int neutralCount,
    required int negativeCount,
    String? analyzedLinkId,
    int? communityPerception,
    int? trust,
    int? contentClarity,
    String? executiveSummary,
    CreatorIntelligenceReport? creatorReport,
  });

  Future<AudienceScoreSnapshot?> loadAudienceScoreSnapshotWithBody(
    String ownerId,
    String snapshotId,
  );

  Stream<List<AudienceScoreSnapshot>> audienceScoreHistoryStream(
    String ownerId, {
    int limit = 36,
  });

  Future<int> seedDemoFeedbacksForOwner(String ownerId);

  Future<int> seedBulkDemoFeedbacksForOwner(
    String ownerId, {
    int count = 1000,
    int? seed,
  });
}
