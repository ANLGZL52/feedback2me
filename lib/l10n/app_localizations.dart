import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';

/// Türkçe ve İngilizce metinler. Dil seçimi app_state.localeNotifier ile yapılır.
class L10n {
  L10n._();

  static const String _localeKey = 'app_locale';

  static Locale? get _override => localeNotifier.value;
  static set _override(Locale? v) => localeNotifier.value = v;

  /// UI ve rapor üretimi için normalize dil: yalnızca `tr` veya `en`.
  static String languageCodeForApp(BuildContext context) {
    final locale = _override ?? Localizations.localeOf(context);
    return locale.languageCode == 'tr' ? 'tr' : 'en';
  }

  /// [MaterialApp] ağacı yokken (web splash vb.) cihaz diline göre metin.
  static String boot(String key) {
    final code =
        SchedulerBinding.instance.platformDispatcher.locale.languageCode;
    final isTr = code == 'tr';
    final map = isTr ? _tr : _en;
    return map[key] ?? _en[key] ?? _tr[key] ?? key;
  }

  static String get(BuildContext context, String key) {
    final locale = _override ?? Localizations.localeOf(context);
    final isTr = locale.languageCode == 'tr';
    final map = isTr ? _tr : _en;
    return map[key] ?? _en[key] ?? key;
  }

  static Future<void> setLocale(Locale? locale) async {
    _override = locale;
    await _prefs?.setString(_localeKey, locale?.languageCode ?? '');
  }

  static Future<void> loadSavedLocale() async {
    final code = _prefs?.getString(_localeKey);
    if (code != null && code.isNotEmpty) {
      _override = Locale(code);
    }
  }

  static dynamic _prefs;
  static void setPrefs(dynamic prefs) => _prefs = prefs;

  static const Map<String, String> _en = {
    'appTitle': 'Feedback2Me',
    'appSubtitle': 'Personal feedback link',
    'login': 'Log in',
    'logout': 'Log out',
    'back': 'Back',
    'loginSubtitle': 'Log in to create links and collect feedback for free.',
    'loginGoogle': 'Log in with Google',
    'loginApple': 'Log in with Apple',
    'continueWithoutLogin': 'Continue without logging in',
    'loginFailedGoogle': 'Google sign-in failed',
    'loginFailedApple': 'Apple sign-in failed',
    'home': 'Home',
    'profile': 'Profile',
    'createLinkCardTitle': 'Create my Feedback2Me link',
    'createLinkCardSubtitle': 'Create your profile and collect honest feedback from everyone with one link. Free.',
    'createLinkTierHint':
        'One free demo link per account (10 min, one comment). After that, purchase premium link credits (24 hours, multiple comments).',
    'tagline': 'Create one link in your name and let everyone share their thoughts.\nAI turns all feedback into a report for you.',
    'premiumAndCreateLink': 'Sign in',
    'afterLoginUseNewLinkButton':
        'Signed in. Tap “Create new link” when you want a new feedback link.',
    'writeFeedbackFromLink': 'Write feedback from link',
    'footerPremium': 'Free: link creation, AI reporting and sharing.',
    'footerGuests': 'Anyone can click the link and write comments for free.',
    'free': 'Free',
    'headerBadgeDemo': 'Demo',
    'headerBadgePremium': 'Premium',
    'headerBadgeDemoTooltip':
        'One-time free demo: 10 minutes, one comment. Then purchase premium link credits.',
    'headerBadgeNeedCredit': 'Buy link',
    'headerBadgeNeedCreditTooltip':
        'Free demo used. Purchase a premium link credit to continue.',
    'creditSheetTitle': 'Premium link required',
    'creditSheetBody':
        'You already used your one-time demo (10 min, one comment). Buy a premium link credit for a 24-hour link with multiple comments.',
    'creditSheetOpenPremium': 'Plans & purchase',
    'linkRequiresCredit':
        'You need a premium link or subscription. Open Plans to continue.',
    'linkCreditsCount': 'Credits',
    'demoSheetTitle': 'Demo plan',
    'demoSheetBodyLoggedIn':
        'Your account gets one free demo link (10 minutes, one comment). After that, premium links are paid per link or included with a subscription.',
    'demoSheetBodyGuest':
        'Sign in to create your one free demo link. Then purchase premium links or subscribe.',
    'demoSheetGoPremium': 'Plans & purchase',
    'demoSheetLoginFirst': 'Sign in',
    'headerBadgePremiumTooltip': '24-hour links, multiple comments (subscription or link credits).',
    'premium': 'Premium',
    'createProfile': 'Create your profile',
    'createProfileSubtitle': 'Create your personal feedback link for free.',
    'nameLabel': 'Full name',
    'nameHint': 'e.g. John Doe',
    'handleLabel': 'Display handle (optional)',
    'handleHint': '@johndoe',
    'continueToPremium': 'Continue',
    'createProfileNote': 'We only collect your profile. All features are free.',
    'linkCreated': 'New link created (copied)',
    'linkCreateFailed': 'Failed to create link',
    'linkCreateFailedInterop':
        'Could not create the link on web. Try again; if it persists, open the browser console (F12) for the real error.',
    'linkCreateAuthMismatch':
        'Session does not match your account. Sign out and sign in again.',
    'linkCreateFirestoreDeployHint':
        'Often fixed by publishing rules: in project folder run firebase deploy --only firestore:rules',
    'reportSummary': 'Report summary',
    'feedbackCollected': 'feedback collected.',
    'reportMoreDetail': 'More feedback will produce longer, AI-powered reports.',
    'close': 'Close',
    'goToAnalysis': 'Go to growth analysis',
    'reportFailed': 'Failed to create report',
    'dashboardTitle': 'Feedback2Me dashboard',
    'premiumUser': 'User',
    'premiumActive': 'Free • Active',
    'yourLinks': 'Your links',
    'activeLink': 'Active feedback link',
    'noLinksYet': 'No links created yet.',
    'created': 'Created',
    'newLink': 'Create new link',
    'linkCopied': 'Link copied',
    'shareLink': 'Share link',
    'createReport': 'Create report',
    'linksInfo': 'Create new links anytime. Old links can be deactivated.',
    'campaigns': 'Campaigns and change',
    'exampleReport': 'View sample report',
    'previousReports': 'My previous reports',
    'noReportsYet': 'No reports created yet.',
    'firstReportNote': 'You will see your reports here after your first feedback period.',
    'share': 'Share',
    'saveToGallery': 'Save to gallery',
    'saveToGallerySubtitle': 'Saves the image to your photo gallery.',
    'shareTwitter': 'Share on Twitter / X',
    'shareInstagram': 'Share on Instagram',
    'shareOther': 'Other apps',
    'shareOtherSubtitle': 'WhatsApp, messages, etc.',
    'savedToGallery': 'Report image saved to gallery.',
    'galleryError': 'Could not save to gallery',
    'shareAnalysis': 'Share analysis as image',
    'imageError': 'Something went wrong creating the image.',
    'reportAnalysisTitle': 'Growth analysis report',
    'comparePeriods': 'Compare periods',
    'feedbackFormTitle': 'Write feedback',
    'feedbackFormSubtitle': 'Enter the link code (e.g. feedback.to/xxx or just the code).',
    'linkCodeHint': 'Link code',
    'yourName': 'Your name',
    'relation': 'How do you know them?',
    'relationUnknown': 'Unknown',
    'mood': 'Overall mood',
    'yourFeedback': 'Your feedback',
    'send': 'Send',
    'feedbackSent': 'Thank you, your feedback was sent.',
    'feedbackError': 'Could not send feedback.',
    'feedbackFormFooterDiscover': 'Want your own feedback link and AI reports?',
    'feedbackFormOpenApp': 'Open Feedback2Me',
    'feedbackFormGoPremium': 'Go Premium & try it yourself',
    'feedbackFormCouldNotOpenLink': 'Could not open link.',
    'feedbackFormIntroLead':
        'This screen is for sharing honest feedback about the person who sent you the link. They use Feedback2Me to collect comments in one place and turn them into an AI summary—without seeing who wrote each message unless you add your name.',
    'feedbackFormHowItWorksTitle': 'How it works',
    'feedbackFormHowStep1':
        'Paste or type the feedback link or code they shared (full URL is fine).',
    'feedbackFormHowStep2':
        'Write your thoughts. Feedback is shared with the link owner; your name is optional.',
    'feedbackFormHowStep3':
        'If comments contain profanity or severe insults, AI may soften the wording before it appears in their report.',
    'feedbackFormPrivacyTitle': 'Privacy & AI',
    'feedbackFormPrivacyBody':
        'You do not have to use your real name. Messages are kept for the owner\'s reports and analytics. Very harsh language may be toned down so the report stays useful and respectful.',
    'feedbackFormLinkLabel': 'Feedback link',
    'feedbackFormLinkHint': 'e.g. feedback.to/abc12 or paste the full link',
    'feedbackFormNameLabel': 'Your name (optional)',
    'feedbackFormNameHint': 'You can leave this blank',
    'feedbackFormRelationLabel':
        'Relationship (friend, colleague, customer…)',
    'feedbackFormMoodQuestion': 'How do you feel overall?',
    'moodNegative': 'Negative',
    'moodNeutral': 'Neutral',
    'moodPositive': 'Positive',
    'feedbackFormThoughtsLabel': 'Your thoughts',
    'feedbackFormThoughtsHint':
        'What works well, what could improve? Examples help.\nAt least 10 characters.',
    'feedbackFormTooShort': 'Please write a bit more—at least 10 characters.',
    'feedbackFormInvalidLink':
        'Enter a valid feedback link (e.g. feedback.to/abc12 or the code).',
    'feedbackFormLinkNotFound': 'This link was not found or is no longer active.',
    'feedbackFormLinkExpired': 'This link has expired. Ask the owner for a new or premium link.',
    'feedbackFormSendFailed': 'Could not send:',
    'feedbackFormSuccessTitle': 'Feedback sent',
    'feedbackFormSuccessBody':
        'Your message will reach the link owner anonymously.\nAI may soften very harsh parts before they appear in the report.',
    'creatorSurveySectionTitle': 'Creator context (optional)',
    'creatorSurveySectionSubtitle':
        'More structured signals help AI segment platforms, audience depth, and production perception.',
    'creatorSurveyFamiliarityLabel': 'How long have you followed their content?',
    'creatorSurveyFam_first_time': 'First exposure',
    'creatorSurveyFam_short': 'A few weeks',
    'creatorSurveyFam_medium': 'A few months',
    'creatorSurveyFam_long': 'Long-term follower',
    'creatorSurveyPlatformsLabel': 'Where do you follow them? (multi-select)',
    'creatorSurveyPlat_instagram': 'Instagram',
    'creatorSurveyPlat_tiktok': 'TikTok',
    'creatorSurveyPlat_youtube': 'YouTube',
    'creatorSurveyPlat_twitch': 'Twitch',
    'creatorSurveyPlat_x': 'X / Twitter',
    'creatorSurveyPlat_linkedin': 'LinkedIn',
    'creatorSurveyPlat_other': 'Other / web',
    'creatorSurveyFrequencyLabel': 'How often do you consume their content?',
    'creatorSurveyFreq_rare': 'Rarely',
    'creatorSurveyFreq_monthly': 'A few times a month',
    'creatorSurveyFreq_weekly': 'A few times a week',
    'creatorSurveyFreq_daily': 'Almost daily',
    'creatorSurveyFocusLabel':
        'Which content formats could suit them better? (multi-select)',
    'creatorSurveyFocusHint':
        'Your recommendation—where they could grow, not only what they post today.',
    'creatorSurveyFocus_education': 'Education / how-to',
    'creatorSurveyFocus_entertainment': 'Entertainment',
    'creatorSurveyFocus_lifestyle': 'Lifestyle / vlog',
    'creatorSurveyFocus_tech': 'Tech / product',
    'creatorSurveyFocus_business': 'Business / career',
    'creatorSurveyFocus_gaming': 'Gaming',
    'creatorSurveyFocus_creative': 'Creative / art',
    'creatorSurveyFocus_arts': 'Music / performance',
    'creatorSurveyScoresTitle': 'Rate 1–5 (optional, skip if unsure)',
    'creatorSurveyScoreScale': '1 low · 5 high',
    'creatorSurveyScore_production': 'Production (audio, video, editing)',
    'creatorSurveyScore_clarity': 'Message clarity',
    'creatorSurveyScore_trust': 'Trust / authenticity',
    'creatorSurveyScore_engagement': 'Fun / keeps attention',
    'creatorSurveyScore_consistency': 'Consistency / rhythm',
    'creatorSurveyScoreClear': 'Clear',
    'language': 'Language',
    'turkish': 'Türkçe',
    'english': 'English',
    'systemLanguage': 'System default',
    'settings': 'Settings',
    'settingsSubtitle': 'Language, account and app information.',
    'settingsLanguage': 'Language',
    'settingsAccount': 'Account',
    'settingsAccountGuest': 'Sign in to create links and sync your feedback pool.',
    'settingsIntro': 'Introduction',
    'settingsReplayIntro': 'View intro again',
    'settingsReplayIntroHint': 'Short walkthrough of what Feedback2Me offers.',
    'settingsLegal': 'Legal & support',
    'settingsPrivacyPolicy': 'Privacy policy',
    'settingsPrivacyPolicyHint':
        'How data is collected, used, and deletion requests are handled.',
    'settingsTerms': 'Terms of use',
    'settingsTermsHint': 'Subscription and product usage terms.',
    'settingsSupport': 'Contact support',
    'settingsSupportHint': 'Email support for account or billing issues.',
    'settingsLinkOpenFailed': 'Could not open the link.',
    'settingsLegalFallbackBody':
        'The document could not be opened in the browser. You can view the full text at the URL below, or contact support for assistance.',
    'settingsLegalOpenBrowser': 'Try opening in browser',
    'settingsAbout': 'About',
    'settingsAboutBody':
        'Collect anonymous feedback with one link, then explore AI-powered audience insights and growth trends.',
    'settingsPrivacyNote':
        'Feedback texts are stored for your reports. You manage your links and data from your account.',
    'appVersion': 'v1.0.0',
    'linkDetailTitle': 'Link details',
    'linkCreatedAt': 'Created',
    'feedbackCountLabel': 'Comments received',
    'lastFeedbackAt': 'Last comment',
    'linkTitleLabel': 'Title',
    'copyLink': 'Copy link',
    'linkDelete': 'Remove link',
    'linkDeleteTitle': 'Remove this link?',
    'linkDeleteBody':
        'The link will stop working. Existing comments stay in your pool for reports. This cannot be undone.',
    'cancel': 'Cancel',
    'linkDeleted': 'Link removed.',
    'linkDeleteFailed': 'Could not remove link',
    'linkDetails': 'Details',
    'feedbacksShort': 'comments',
    'linkPlanBannerDemo': 'DEMO LINK',
    'linkPlanBannerDemoSub': '10 minutes · One feedback only · Then the link closes',
    'linkPlanBannerPremium': 'PREMIUM LINK',
    'linkPlanBannerPremiumSub': '24 hours · Multiple comments until it expires',
    'linkPlanBannerLegacy': 'OLDER LINK',
    'linkPlanBannerLegacySub':
        'Created before plan labels · May not match current demo rules',
    'linkTileDemoHint': 'Demo · 10 min · one response',
    'linkTilePremiumUntil': 'Premium · active until',
    'linkValidUntilShort': 'Valid until',
    'linkCountdownRemaining': 'Time left:',
    'linkCountdownCompactPrefix': 'Left:',
    'linkCountdownExpired': 'Expired — link no longer accepts feedback',
    'createdLinkDemoRules':
        'Demo link: 10 minutes and one feedback only. Next links require a purchase or subscription — premium links stay open 24 hours with multiple responses.',
    'createdLinkPremiumRules':
        'Premium link: open for 24 hours; you can collect multiple comments until it expires.',
    'createdLinkPremiumPitch':
        'This link is your one-time free demo. Later links need a paid premium link or subscription for 24-hour multi-comment links.',
    'createdLinkOpenPremium': 'Plans & purchase',
    'shareAudienceAnalysis': 'Share analysis',
    'audienceShareSubject': 'Feedback2Me — Audience analysis',
    'audienceShareHeading': 'Follower comment analysis',
    'audienceSharePool': 'Comments analyzed',
    'audienceShareMoodSplit': 'Positive / neutral / negative',
    'audienceShareOverall': 'Overall score',
    'audienceSharePm': 'Positive momentum',
    'audienceShareRc': 'Negative control',
    'audienceShareDd': 'Sample strength',
    'audienceSharePerception': 'Perception scores (community / trust / clarity)',
    'audienceShareSummary': 'Executive summary',
    'audienceShareThemes': 'Themes',
    'audienceShareActions': 'Action ideas',
    'audienceShareDelta': 'Change vs previous analysis',
    'audienceShareFooter': '— Feedback2Me',
    'bootErrorTitle': 'Error (copy and share this text):\n\n',
    'webErrorLead': 'Error:\n\n',
    'webLoadSlowTitle': 'Loading is taking a while',
    'webLoadSlowBody': 'Refresh the page (F5) or tap the button below.',
    'webRefresh': 'Refresh',
    'webLoadFailedTitle': 'Could not load',
    'webLoadF5': 'Press F5 to refresh',
    'loading': 'Loading…',
    'railwayLoginSnack':
        'Signed in, but the server (Railway) session could not be started.\n'
        '• In builds, --dart-define=DEV_AUTH_SECRET must match Railway\n'
        '• Server must have ALLOW_DEV_AUTH=true\n'
        '• Google account must have an email (Apple private relay breaks this bridge)',
    'yes': 'Yes',
    'bulkTestDataTitle': 'Bulk test data',
    'bulkTestDataBody':
        '{n} random comments will be written to the backend. This may take a few seconds. Continue?',
    'commentsWriting': 'Writing comments…',
    'snackCreateLinkFirst': 'Create a link first.',
    'snackCommentsAdded': '{n} comments added.',
    'profileSectionTitle': 'Profile',
    'profileDefaultUser': 'User',
    'profileEditHint': 'Edit profile details in Settings.',
    'feedbackPoolSectionTitle': 'Comment pool',
    'devSeedTitle': 'Developer: test data',
    'devSeedBody':
        'Add sample comments to Firestore to try analysis screens without typing each one. You need at least one feedback link first.',
    'snackCreateLinkFirstLong':
        'Create a link from Home first, then try again.',
    'snackSampleCommentsAdded': '{n} sample comments added. List refreshed.',
    'snackCouldNotAdd': 'Could not add: {e}',
    'devSeed12': '12 sample comments (quick)',
    'bulkBotGenerate': 'Generate {n} bot comments (batch)',
    'comparePeriodsExampleTitle': 'For example:',
    'comparePeriodsExampleBody':
        '• Period 1: Mar 1–21 • “First impressions”\n'
        '• Period 2: Mar 22–Apr 11 • “After improvements”\n\n'
        'AI will compare periods and report whether changes are reflected in feedback.',
    'viewSampleChangeReport': 'View sample change report',
    'firstReportExtraHint':
        'When you run «Follower comment analysis» from Home, the record appears here.',
    'runAnalysis': 'Run analysis',
    'savedAnalysesLine': '{n} saved analyses',
    'growthAnalysisNav': 'Growth analysis',
    'scoreOverallComments': '{score}/100 · {count} comments',
    'allHistoryCompare': 'Full history & compare →',
    'compareNoSavedBody':
        'No saved analyses yet. Collect comments in the pool, then run «Follower comment analysis» — audience scores and growth comparison appear here.',
    'runFollowerAnalysis': 'Run follower analysis',
    'goGrowthScreen': 'Open growth screen',
    'lastAnalysisTitle': 'Latest analysis snapshot',
    'lastAnalysisBody':
        'Values below come from your last saved run; open the record or analysis screen for full text.',
    'fullReport': 'Full report',
    'growthShort': 'Growth',
    'poolTotal': 'Total {n} comments in pool',
    'poolPreview': ' · Preview: {m}',
    'poolGrowing': '{n} comments in pool',
    'refreshTooltip': 'Refresh',
    'poolReadError': 'Could not load comment pool: {e}',
    'poolEmptyHint': 'No comments yet. They will appear here as you share your link.',
    'poolMore': '+{n} more comments',
    'aiAudienceAnalysisRun': 'AI follower comment analysis',
    'audienceFetchTitle': 'Loading comment pool',
    'audienceFetchSubtitle': 'Fetching all feedback from the server…',
    'audienceLoadingTitle': 'Preparing analysis',
    'audienceLoadingSubtitle': 'This can take several minutes depending on volume.',
    'generatedByLine': 'Generated by Feedback2Me',
    'growthSummaryBadge': 'Feedback2Me · Growth snapshot',
    'pointsDelta': '{delta} pts vs previous analysis',
    'audienceAppBarTitle': 'Follower comment analysis',
    'relationDistributionTitle': 'Relation breakdown',
    'retry': 'Try again',
    'runFollowerAnalysisShort': 'Run follower analysis',
    'savedReportAppBar': 'Saved follower report',
    'reportLoadFailed': 'Could not load report: {e}',
    'noSavedAudienceRun':
        'No saved follower analysis yet. Collect comments in the pool first, then run analysis from Profile.',
    'reportAnalysisHistoryHint':
        'Each «Follower comment analysis» run is saved. Below you can compare recent runs, '
        'open the shareable summary card, and browse past reports.',
    'reportAnalysisLoginRequired':
        'Sign in to view follower analysis history and progress vs your previous report.',
    'historyLoadFailed': 'Could not load history: {e}',
    'currentScoreLine': 'Current score: {score}/100 · {count} comments',
    'errorGeneric': 'Error: {e}',
    'iapStoreUnavailable': 'Store unavailable. Please check your internet connection and try again.',
    'iapProductsComingSoon':
        'Premium plans are being set up and will be available shortly. Please try again later.',
    'iapLoadError': 'Could not load products. Please check your connection and try again.',
    'iapLoginRequired': 'You must sign in first.',
    'iapPaymentOpened':
        'Payment sheet opened. Rights will apply to your account when complete.',
    'iapPurchaseStartFailed': 'Purchase could not be started.',
    'iapRestoreDone':
        'Restore finished. Premium updates if an active subscription exists.',
    'iapRestoreError': 'Restore error: {e}',
    'iapScreenTitle': 'Premium',
    'iapCreditTitle': 'Premium link credit',
    'iapCreditSubtitle':
        'Adds +1 link credit to your account (one link, 24 hours, multiple comments).',
    'iapRestoreButton': 'Restore purchases (Apple / Google)',
    'iapAppleFootnote':
        'Payments are processed through your Apple ID.',
    'iapDebugSection': 'Developer (debug only)',
    'iapBuy': 'Buy',
    'iapNotInStore': 'Not in store yet: {label}',
    'iapBullets':
        '• First account: one free demo link (10 min, one comment)\n'
        '• Purchase link credits: each credit = one premium link (24 hours, multiple comments)',
    'iapHeadline': 'Premium link credits',
    'iapPaymentsNote':
        'Payments are only via Apple App Store and Google Play. Open the app on iPhone or Android to purchase from this screen.',
    'iapAndroidFootnote':
        'Payments are processed with your Google account.',
    'audienceGrowthScoreTitle': 'Audience growth score',
    'audienceGrowthScoreBody':
        'Calculated from positive rate, negative pressure, and comment volume; '
        'each follower comment analysis run is saved.',
    'growthVsPreviousTitle': 'Progress vs previous report',
    'growthVsPreviousEmptyBody':
        'After you run «Follower comment analysis» at least twice, overall score, '
        'sentiment split and (when available) cover trio metrics are compared with the previous save.',
    'growthComparedDates': 'Latest ({cur}) vs previous ({prev}).',
    'growthDeltaOverallScore': 'Overall growth score',
    'growthDeltaPmScore': 'Positive momentum (score)',
    'growthDeltaRcScore': 'Negative control (score)',
    'growthDeltaDdScore': 'Sample strength (score)',
    'growthDeltaSupportivePct': 'Supportive comment share (%)',
    'growthDeltaRiskPct': 'Negative comment share (%)',
    'growthCoverTrioLabel': 'Cover trio (report)',
    'growthPerceptionCommunity': 'Community perception',
    'growthPerceptionTrust': 'Trust',
    'growthPerceptionClarity': 'Content clarity',
    'perceptionScoresTitle': 'Perception scores',
    'perceptionScoresSubtitle': 'Three indicators of how followers read you.',
    'growthHistoryTitle': 'Growth history',
    'growthHistoryHintMulti':
        'As your pool grows with new links, track score changes over time here.',
    'growthHistoryHintSingle':
        'After the next run you will see a sparkline; regular runs make the trend clearer.',
    'historyCommentsCount': '· {n} comments',
    'historyOpenReport': 'Report ›',
  };

  static const Map<String, String> _tr = {
    'appTitle': 'Feedback2Me',
    'appSubtitle': 'Kişisel feedback linki',
    'login': 'Giriş yap',
    'logout': 'Çıkış yap',
    'back': 'Geri',
    'loginSubtitle': 'Giriş yaparak ücretsiz link oluştur ve feedback topla.',
    'loginGoogle': 'Google ile giriş yap',
    'loginApple': 'Apple ile giriş yap',
    'continueWithoutLogin': 'Giriş yapmadan devam et',
    'loginFailedGoogle': 'Google ile giriş başarısız',
    'loginFailedApple': 'Apple ile giriş başarısız',
    'home': 'Ana sayfa',
    'profile': 'Profil',
    'createLinkCardTitle': 'Feedback2Me linkimi oluştur',
    'createLinkCardSubtitle': 'Profilini oluştur, tek linkten herkesten dürüst geri bildirim topla. Ücretsiz.',
    'createLinkTierHint':
        'Hesap başına tek ücretsiz demo link (10 dk, tek yorum). Sonrasında premium link kredisi satın alarak 24 saatlik çoklu yorum linkleri oluşturabilirsiniz.',
    'tagline': 'Feedback2Me ile kendi adınla tek bir link oluştur, herkes düşüncesini yazsın.\nYapay zeka tüm yorumları senin için rapora çevirsin.',
    'premiumAndCreateLink': 'Giriş yap',
    'afterLoginUseNewLinkButton':
        'Giriş yapıldı. Yeni bir feedback linki için "Yeni link oluştur" düğmesine dokun.',
    'writeFeedbackFromLink': 'Gelen linkten feedback yaz',
    'footerPremium': 'Ücretsiz: link oluşturma, AI raporlama ve paylaşım.',
    'footerGuests': 'Herkes linke tıklayıp ücretsiz yorum yazabilir.',
    'free': 'Ücretsiz',
    'headerBadgeDemo': 'Demo',
    'headerBadgePremium': 'Premium',
    'headerBadgeDemoTooltip':
        'Tek seferlik ücretsiz demo: 10 dk, tek yorum. Sonra premium link kredisi satın al.',
    'headerBadgeNeedCredit': 'Link satın al',
    'headerBadgeNeedCreditTooltip':
        'Ücretsiz demo kullanıldı. Devam etmek için premium link kredisi satın al.',
    'creditSheetTitle': 'Premium link gerekli',
    'creditSheetBody':
        'Tek seferlik demo hakkını kullandın (10 dk, tek yorum). Devam etmek için premium link kredisi satın al (24 saat, çoklu yorum).',
    'creditSheetOpenPremium': 'Planlar ve satın al',
    'linkRequiresCredit':
        'Premium link veya abonelik gerekir. Devam etmek için Planlar ekranını aç.',
    'linkCreditsCount': 'Kredi',
    'demoSheetTitle': 'Demo plan',
    'demoSheetBodyLoggedIn':
        'Hesabında tek ücretsiz demo link var (10 dakika, tek yorum). Sonrasında link başına ücret veya abonelikle sınırsız premium link.',
    'demoSheetBodyGuest':
        'Giriş yaparak tek ücretsiz demo linkini oluştur. Sonra premium link veya abonelik alabilirsin.',
    'demoSheetGoPremium': 'Planlar ve satın al',
    'demoSheetLoginFirst': 'Giriş yap',
    'headerBadgePremiumTooltip':
        '24 saatlik link, çoklu yorum (abonelik veya link kredisi).',
    'premium': 'Premium',
    'createProfile': 'Profilini oluştur',
    'createProfileSubtitle': 'Kendi adınla ücretsiz kişisel feedback linki oluştur.',
    'nameLabel': 'Ad Soyad',
    'nameHint': 'Örn. Cankat Yılmaz',
    'handleLabel': 'Görünür kullanıcı adı (opsiyonel)',
    'handleHint': '@cankatyilmaz',
    'continueToPremium': 'Devam et',
    'createProfileNote': 'Sadece profil bilgini alıyoruz. Tüm özellikler ücretsiz.',
    'linkCreated': 'Yeni link oluşturuldu (kopyalandı)',
    'linkCreateFailed': 'Link oluşturulamadı',
    'linkCreateFailedInterop':
        'Web üzerinde link oluşturulamadı. Tekrar deneyin; devam ederse gerçek hatayı görmek için tarayıcı konsolunu (F12) açın.',
    'linkCreateAuthMismatch':
        'Oturum ile hesap uyuşmuyor. Çıkış yapıp tekrar giriş yapın.',
    'linkCreateFirestoreDeployHint':
        'Çoğu zaman: proje klasöründe firebase deploy --only firestore:rules (Console kuralları bu repodaki firestore.rules ile aynı olmalı).',
    'reportSummary': 'Rapor özeti',
    'feedbackCollected': 'yorum toplandı.',
    'reportMoreDetail': 'Yorum sayısı arttıkça AI ile daha uzun ve detaylı rapor üretilecek.',
    'close': 'Kapat',
    'goToAnalysis': 'Gelişim analizi ekranına git',
    'reportFailed': 'Rapor oluşturulamadı',
    'dashboardTitle': 'Feedback2Me paneli',
    'premiumUser': 'Kullanıcı',
    'premiumActive': 'Ücretsiz • Aktif',
    'yourLinks': 'Linklerin',
    'activeLink': 'Aktif feedback linkin',
    'noLinksYet': 'Henüz bir link oluşturulmadı.',
    'created': 'Oluşturuldu',
    'newLink': 'Yeni link oluştur',
    'linkCopied': 'Link kopyalandı',
    'shareLink': 'Linki paylaş',
    'createReport': 'Rapor oluştur',
    'linksInfo': 'İstediğin an yeni link oluşturabilirsin. Eski linkler isteğe göre pasif hale getirilebilir.',
    'campaigns': 'Kampanyalar ve değişim',
    'exampleReport': 'Örnek rapor gör',
    'previousReports': 'Önceki raporlarım',
    'noReportsYet': 'Henüz oluşturulmuş bir rapor yok',
    'firstReportNote': 'İlk feedback dönemini tamamladığında buradan raporlarını göreceksin.',
    'share': 'Paylaş',
    'saveToGallery': 'Galeriye kaydet',
    'saveToGallerySubtitle': 'Görseli fotoğraf galerisine kaydeder',
    'shareTwitter': 'Twitter\'da paylaş',
    'shareInstagram': 'Instagram\'da paylaş',
    'shareOther': 'Diğer uygulamalar',
    'shareOtherSubtitle': 'WhatsApp, mesajlar vb.',
    'savedToGallery': 'Rapor görseli galeriye kaydedildi.',
    'galleryError': 'Galeriye kaydetme',
    'shareAnalysis': 'Analizi görsel olarak paylaş',
    'imageError': 'Görsel oluşturulurken bir hata oldu. Tekrar dener misin?',
    'reportAnalysisTitle': 'Rapor gelişim analizi',
    'comparePeriods': 'Dönemleri karşılaştır',
    'feedbackFormTitle': 'Feedback yaz',
    'feedbackFormSubtitle': 'Link kodunu gir (örn. feedback.to/xxx veya sadece kod).',
    'linkCodeHint': 'Link kodu',
    'yourName': 'Adın',
    'relation': 'Onu nasıl tanıyorsun?',
    'relationUnknown': 'Belirsiz',
    'mood': 'Genel ruh hali',
    'yourFeedback': 'Yorumun',
    'send': 'Gönder',
    'feedbackSent': 'Teşekkürler, geri bildirimin gönderildi.',
    'feedbackError': 'Geri bildirim gönderilemedi.',
    'feedbackFormFooterDiscover':
        'Kendi feedback linkin ve AI raporların mı olsun?',
    'feedbackFormOpenApp': 'Feedback2Me uygulamasını aç',
    'feedbackFormGoPremium': 'Premium ol ve sen de dene',
    'feedbackFormCouldNotOpenLink': 'Bağlantı açılamadı.',
    'feedbackFormIntroLead':
        'Bu ekran, sana linki gönderen kişi hakkında düşüncelerini paylaşman içindir. O kişi Feedback2Me ile tüm yorumları tek yerde toplar ve yapay zekâ ile özetler; ismini yazmadığın sürece kim yazdığını bilmez.',
    'feedbackFormHowItWorksTitle': 'Nasıl çalışır?',
    'feedbackFormHowStep1':
        'Sana gelen feedback linkini veya kodunu yapıştır ya da yaz (tam adres de olur).',
    'feedbackFormHowStep2':
        'Düşüncelerini yaz. İsim isteğe bağlıdır; yorumun link sahibiyle paylaşılır.',
    'feedbackFormHowStep3':
        'Küfür veya çok sert hakaret varsa, metin rapora eklenmeden önce yapay zekâ tarafından yumuşatılabilir.',
    'feedbackFormPrivacyTitle': 'Gizlilik ve yapay zeka',
    'feedbackFormPrivacyBody':
        'Gerçek adını yazmak zorunda değilsin. Yorumlar, link sahibinin raporları ve analizleri için saklanır. Çok sert dil, raporun faydalı ve saygılı kalması için yumuşatılabilir.',
    'feedbackFormLinkLabel': 'Feedback linki',
    'feedbackFormLinkHint': 'örn. feedback.to/abc12 veya tam linki yapıştır',
    'feedbackFormNameLabel': 'Adın (isteğe bağlı)',
    'feedbackFormNameHint': 'Boş bırakabilirsin',
    'feedbackFormRelationLabel':
        'Kişiyle ilişkin (arkadaş, iş arkadaşı, müşteri…)',
    'feedbackFormMoodQuestion': 'Genel hissin nasıl?',
    'moodNegative': 'Olumsuz',
    'moodNeutral': 'Nötr',
    'moodPositive': 'Olumlu',
    'feedbackFormThoughtsLabel': 'Düşüncelerini yaz',
    'feedbackFormThoughtsHint':
        'Ne iyi gidiyor, neler gelişsin istersin? Mümkünse somut örnek ver.\nEn az 10 karakter.',
    'feedbackFormTooShort': 'Biraz daha ayrıntı yazar mısın? En az 10 karakter.',
    'feedbackFormInvalidLink':
        'Lütfen geçerli bir feedback linki gir (örn. feedback.to/abc12 veya kod).',
    'feedbackFormLinkNotFound': 'Bu link bulunamadı veya artık geçerli değil.',
    'feedbackFormLinkExpired':
        'Bu linkin süresi dolmuş. Sahibinden yeni veya premium link isteyin.',
    'feedbackFormSendFailed': 'Gönderilemedi:',
    'feedbackFormSuccessTitle': 'Feedback gönderildi',
    'feedbackFormSuccessBody':
        'Yorumun link sahibine anonim olarak iletilecek.\nÇok sert kısımlar rapora eklenmeden önce yapay zekâ tarafından yumuşatılabilir.',
    'creatorSurveySectionTitle': 'İçerik üreticisi bağlamı (isteğe bağlı)',
    'creatorSurveySectionSubtitle':
        'Platform, izleyici derinliği ve üretim algısı için yapılandırılmış sinyaller; AI raporunu zenginleştirir.',
    'creatorSurveyFamiliarityLabel': 'İçeriklerini ne zamandır takip ediyorsun?',
    'creatorSurveyFam_first_time': 'İlk kez görüyorum',
    'creatorSurveyFam_short': 'Birkaç haftadır',
    'creatorSurveyFam_medium': 'Birkaç aydır',
    'creatorSurveyFam_long': 'Uzun süredir takipçiyim',
    'creatorSurveyPlatformsLabel': 'Hangi kanallarda takip ediyorsun? (çoklu seçim)',
    'creatorSurveyPlat_instagram': 'Instagram',
    'creatorSurveyPlat_tiktok': 'TikTok',
    'creatorSurveyPlat_youtube': 'YouTube',
    'creatorSurveyPlat_twitch': 'Twitch',
    'creatorSurveyPlat_x': 'X (Twitter)',
    'creatorSurveyPlat_linkedin': 'LinkedIn',
    'creatorSurveyPlat_other': 'Diğer / web',
    'creatorSurveyFrequencyLabel': 'İçeriklerini ne sıklıkla tüketiyorsun?',
    'creatorSurveyFreq_rare': 'Nadiren',
    'creatorSurveyFreq_monthly': 'Ayda birkaç kez',
    'creatorSurveyFreq_weekly': 'Haftada birkaç kez',
    'creatorSurveyFreq_daily': 'Neredeyse her gün',
    'creatorSurveyFocusLabel':
        'Hangi içerik türünü yapsa daha iyi olabilir? (çoklu seçim)',
    'creatorSurveyFocusHint':
        'Şu an ne paylaştığından bağımsız; senin önerin — nerede güçlenebilir?',
    'creatorSurveyFocus_education': 'Eğitim / nasıl yapılır',
    'creatorSurveyFocus_entertainment': 'Eğlence',
    'creatorSurveyFocus_lifestyle': 'Yaşam tarzı / vlog',
    'creatorSurveyFocus_tech': 'Teknoloji / ürün',
    'creatorSurveyFocus_business': 'İş / kariyer',
    'creatorSurveyFocus_gaming': 'Oyun',
    'creatorSurveyFocus_creative': 'Yaratıcı / sanat',
    'creatorSurveyFocus_arts': 'Müzik / performans',
    'creatorSurveyScoresTitle': 'Puanla 1–5 (isteğe bağlı, emin değilsen atla)',
    'creatorSurveyScoreScale': '1 düşük · 5 yüksek',
    'creatorSurveyScore_production': 'Üretim kalitesi (ses, görüntü, kurgu)',
    'creatorSurveyScore_clarity': 'Mesaj netliği',
    'creatorSurveyScore_trust': 'Güven / samimiyet',
    'creatorSurveyScore_engagement': 'Eğlence / ilgi çekicilik',
    'creatorSurveyScore_consistency': 'Tutarlılık / yayın düzeni',
    'creatorSurveyScoreClear': 'Temizle',
    'language': 'Dil',
    'turkish': 'Türkçe',
    'english': 'English',
    'systemLanguage': 'Cihaz dili',
    'settings': 'Ayarlar',
    'settingsSubtitle': 'Dil, hesap ve uygulama bilgisi.',
    'settingsLanguage': 'Dil',
    'settingsAccount': 'Hesap',
    'settingsAccountGuest':
        'Link oluşturmak ve geri bildirim havuzunu eşitlemek için giriş yap.',
    'settingsIntro': 'Tanıtım',
    'settingsReplayIntro': 'Tanıtımı tekrar izle',
    'settingsReplayIntroHint': 'Feedback2Me’nin sunduklarına kısa bir tur.',
    'settingsLegal': 'Yasal ve destek',
    'settingsPrivacyPolicy': 'Gizlilik politikası',
    'settingsPrivacyPolicyHint':
        'Verinin nasıl toplandığı, kullanıldığı ve silme taleplerinin yönetimi.',
    'settingsTerms': 'Kullanım şartları',
    'settingsTermsHint': 'Abonelik ve ürün kullanım koşulları.',
    'settingsSupport': 'Destek ile iletişim',
    'settingsSupportHint': 'Hesap veya ödeme sorunları için e-posta desteği.',
    'settingsLinkOpenFailed': 'Bağlantı açılamadı.',
    'settingsLegalFallbackBody':
        'Belge tarayıcıda açılamadı. Tam metni aşağıdaki adresten görüntüleyebilir veya destek ile iletişime geçebilirsiniz.',
    'settingsLegalOpenBrowser': 'Tarayıcıda açmayı dene',
    'settingsAbout': 'Hakkında',
    'settingsAboutBody':
        'Tek linkle anonim geri bildirim topla; yapay zekâ destekli kitle içgörüleri ve gelişim özetlerini keşfet.',
    'settingsPrivacyNote':
        'Yorum metinleri raporların için saklanır. Linklerini ve verilerini hesabından yönetirsin.',
    'appVersion': 'sürüm 1.0.0',
    'linkDetailTitle': 'Link bilgileri',
    'linkCreatedAt': 'Oluşturulma',
    'feedbackCountLabel': 'Gelen yorum',
    'lastFeedbackAt': 'Son yorum',
    'linkTitleLabel': 'Başlık',
    'copyLink': 'Linki kopyala',
    'linkDelete': 'Linki kaldır',
    'linkDeleteTitle': 'Bu link kaldırılsın mı?',
    'linkDeleteBody':
        'Link artık çalışmaz. Mevcut yorumlar raporların için havuzda kalır. Bu işlem geri alınamaz.',
    'cancel': 'Vazgeç',
    'linkDeleted': 'Link kaldırıldı.',
    'linkDeleteFailed': 'Link kaldırılamadı',
    'linkDetails': 'Detay',
    'feedbacksShort': 'yorum',
    'linkPlanBannerDemo': 'DEMO LİNK',
    'linkPlanBannerDemoSub': '10 dakika · Tek geri bildirim · Sonra link kapanır',
    'linkPlanBannerPremium': 'PREMİUM LİNK',
    'linkPlanBannerPremiumSub': '24 saat · Süre dolana kadar birden fazla yorum',
    'linkPlanBannerLegacy': 'ESKİ TİP LİNK',
    'linkPlanBannerLegacySub':
        'Plan etiketinden önce oluşturuldu · Güncel demo kurallarıyla uyumlu olmayabilir',
    'linkTileDemoHint': 'Demo · 10 dk · tek yanıt',
    'linkTilePremiumUntil': 'Premium · geçerlilik',
    'linkValidUntilShort': 'Son geçerlilik',
    'linkCountdownRemaining': 'Kalan süre:',
    'linkCountdownCompactPrefix': 'Kalan:',
    'linkCountdownExpired': 'Süre doldu — link artık yorum kabul etmiyor',
    'createdLinkDemoRules':
        'Demo link: 10 dakika ve tek geri bildirim. Sonraki linkler ücretli premium veya abonelik — premium linkler 24 saat, çoklu yorum.',
    'createdLinkPremiumRules':
        'Premium link: 24 saat açık; süre dolana kadar birden fazla yorum toplayabilirsiniz.',
    'createdLinkPremiumPitch':
        'Bu link tek seferlik ücretsiz demo. Sonraki linkler için ücretli premium link veya abonelik gerekir (24 saat, çoklu yorum).',
    'createdLinkOpenPremium': 'Planlar ve satın al',
    'shareAudienceAnalysis': 'Analizi paylaş',
    'audienceShareSubject': 'Feedback2Me — Takipçi analizi',
    'audienceShareHeading': 'Takipçi yorum analizi',
    'audienceSharePool': 'İncelenen yorum',
    'audienceShareMoodSplit': 'Olumlu / nötr / olumsuz',
    'audienceShareOverall': 'Genel puan',
    'audienceSharePm': 'Olumlu ivme',
    'audienceShareRc': 'Olumsuz kontrol',
    'audienceShareDd': 'Örneklem gücü',
    'audienceSharePerception': 'Algı skorları (topluluk / güven / netlik)',
    'audienceShareSummary': 'Yönetici özeti',
    'audienceShareThemes': 'Temalar',
    'audienceShareActions': 'Önerilen aksiyonlar',
    'audienceShareDelta': 'Önceki analize göre değişim',
    'audienceShareFooter': '— Feedback2Me',
    'bootErrorTitle': 'Hata (bu metni kopyalayıp paylaş):\n\n',
    'webErrorLead': 'Hata:\n\n',
    'webLoadSlowTitle': 'Yükleme uzun sürdü',
    'webLoadSlowBody': 'Sayfayı yenileyin (F5) veya aşağıdaki düğmeye tıklayın.',
    'webRefresh': 'Yenile',
    'webLoadFailedTitle': 'Yüklenemedi',
    'webLoadF5': 'F5 tuşuna basarak yenileyin',
    'loading': 'Yükleniyor…',
    'railwayLoginSnack':
        'Giriş tamamlandı ancak sunucu (Railway) oturumu açılamadı.\n'
                    '• Derlemede --dart-define=DEV_AUTH_SECRET, Railway’deki ile aynı olmalı\n'
        '• Sunucuda ALLOW_DEV_AUTH=true olmalı\n'
        '• Google hesabında e-posta olmalı (Apple gizli e-posta bu köprüde çalışmaz)',
    'yes': 'Evet',
    'bulkTestDataTitle': 'Toplu test verisi',
    'bulkTestDataBody':
        'Rastgele {n} yorum arka uca yazılacak. Birkaç saniye sürebilir. Devam?',
    'commentsWriting': 'Yorumlar yazılıyor…',
    'snackCreateLinkFirst': 'Önce bir link oluştur.',
    'snackCommentsAdded': '{n} yorum eklendi.',
    'profileSectionTitle': 'Profil',
    'profileDefaultUser': 'Kullanıcı',
    'profileEditHint': 'Profil bilgilerini düzenlemek için ayarlara gidin.',
    'feedbackPoolSectionTitle': 'Yorum havuzu',
    'devSeedTitle': 'Geliştirici: test verisi',
    'devSeedBody':
        'Tek tek yorum yazmadan analiz ekranlarını denemek için örnek yorumları arka uca ekleyebilirsin. Önce en az bir feedback linkin olmalı.',
    'snackCreateLinkFirstLong':
        'Önce ana sayfadan bir link oluştur, sonra tekrar dene.',
    'snackSampleCommentsAdded': '{n} örnek yorum eklendi. Listeyi yeniledik.',
    'snackCouldNotAdd': 'Eklenemedi: {e}',
    'devSeed12': '12 örnek yorum (hızlı)',
    'bulkBotGenerate': '{n} bot yorumu üret (batch)',
    'comparePeriodsExampleTitle': 'Örneğin:',
    'comparePeriodsExampleBody':
        '- 1. dönem: 01–21 Mart • “İlk izlenim”\n'
        '- 2. dönem: 22 Mart–11 Nisan • “Geliştirdikten sonra”\n\n'
        'Yapay zeka bu dönemleri karşılaştırarak, '
        'yaptığın değişikliklerin insanlara gerçekten yansıyıp yansımadığını '
        'senin için raporlayacak.',
    'viewSampleChangeReport': 'Örnek değişim raporu gör',
    'firstReportExtraHint':
        'Ana sayfadan «Takipçi Yorum Analizi» çalıştırdığında kayıt burada görünür.',
    'runAnalysis': 'Analiz yap',
    'savedAnalysesLine': '{n} kayıtlı analiz',
    'growthAnalysisNav': 'Gelişim analizi',
    'scoreOverallComments': '{score}/100 · {count} yorum',
    'allHistoryCompare': 'Tüm geçmiş ve kıyas →',
    'compareNoSavedBody':
        'Henüz kayıtlı analiz yok. Havuzda yorum topladıktan sonra «Takipçi Yorum Analizi» çalıştır; dinleyici puanı, algı skorları ve gelişim kıyası burada görünür.',
    'runFollowerAnalysis': 'Takipçi analizini çalıştır',
    'goGrowthScreen': 'Gelişim ekranına git',
    'lastAnalysisTitle': 'Son analiz özeti',
    'lastAnalysisBody':
        'Aşağıdaki değerler kayıtlı son çalıştırmandan gelir; tam metin raporu için kayda veya analiz ekranına gidin.',
    'fullReport': 'Tam rapor',
    'growthShort': 'Gelişim',
    'poolTotal': 'Toplam {n} yorum havuzda',
    'poolPreview': ' · Önizleme: {m}',
    'poolGrowing': '{n} yorum havuzda birikti',
    'refreshTooltip': 'Yenile',
    'poolReadError': 'Yorum havuzu okunamadı: {e}',
    'poolEmptyHint':
        'Henüz yorum yok. Linkini paylaştıkça bu havuz dolacak.',
    'poolMore': '+{n} yorum daha',
    'aiAudienceAnalysisRun': 'AI Takipçi Yorum Analizi Oluştur',
    'audienceFetchTitle': 'Yorum havuzu yükleniyor',
    'audienceFetchSubtitle': 'Sunucudan tüm geri bildirimler alınıyor…',
    'audienceLoadingTitle': 'Analiz hazırlanıyor',
    'audienceLoadingSubtitle':
        'Bu işlem veri miktarına göre birkaç dakika sürebilir.',
    'generatedByLine': 'Generated by Feedback2Me',
    'growthSummaryBadge': 'Feedback2Me · Gelişim özeti',
    'pointsDelta': 'Önceki analize göre: {delta} puan',
    'audienceAppBarTitle': 'Takipçi Yorum Analizi',
    'relationDistributionTitle': 'İlişki bazlı dağılım',
    'retry': 'Tekrar dene',
    'runFollowerAnalysisShort': 'Takipçi analizini çalıştır',
    'savedReportAppBar': 'Kayıtlı takipçi raporu',
    'reportLoadFailed': 'Rapor yüklenemedi: {e}',
    'noSavedAudienceRun':
        'Henüz kayıtlı takipçi analizi yok. Önce havuzda yorum topla, '
        'ardından Profil’den analizi çalıştır.',
    'reportAnalysisHistoryHint':
        'Her «Takipçi Yorum Analizi» çalıştırman kaydedilir. Aşağıda son kayıtların kıyası, '
        'paylaşılabilir özet kartı ve geçmiş raporları açma yer alır.',
    'reportAnalysisLoginRequired':
        'Takipçi analizi geçmişi ve önceki rapora göre gelişim için giriş yapmalısın.',
    'historyLoadFailed': 'Geçmiş yüklenemedi: {e}',
    'currentScoreLine': 'Güncel puan: {score}/100 · {count} yorum',
    'errorGeneric': 'Hata: {e}',
    'iapStoreUnavailable':
        'Mağaza kullanılamıyor. İnternet bağlantınızı kontrol edip tekrar deneyin.',
    'iapProductsComingSoon':
        'Premium planlar hazırlanıyor ve kısa sürede kullanılabilir olacak. Lütfen daha sonra tekrar deneyin.',
    'iapLoadError': 'Ürünler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
    'iapLoginRequired': 'Önce giriş yapmalısın.',
    'iapPaymentOpened':
        'Ödeme ekranı açıldı. Tamamlanınca haklar hesabına işlenecek.',
    'iapPurchaseStartFailed': 'Satın alma başlatılamadı.',
    'iapRestoreDone':
        'Geri yükleme tamamlandı. Abonelik varsa premium güncellenir.',
    'iapRestoreError': 'Geri yükleme hatası: {e}',
    'iapScreenTitle': 'Premium',
    'iapCreditTitle': 'Premium link kredisi',
    'iapCreditSubtitle':
        'Hesabına +1 link kredisi eklenir (bir link, 24 saat, çoklu yorum).',
    'iapRestoreButton': 'Satın alımları geri yükle (Apple / Google)',
    'iapAppleFootnote':
        'Ödemeler Apple kimliğin üzerinden işlenir.',
    'iapDebugSection': 'Geliştirici (yalnızca debug)',
    'iapBuy': 'Satın al',
    'iapNotInStore': 'Mağazada henüz yok: {label}',
    'iapBullets':
        '• İlk hesap: tek ücretsiz demo link (10 dk, bir yorum)\n'
        '• Link kredisi satın al: her kredi = bir premium link (24 saat, çoklu yorum)',
    'iapHeadline': 'Premium link kredisi',
    'iapPaymentsNote':
        'Ödeme yalnızca Apple App Store ve Google Play üzerinden yapılır. '
        'iPhone veya Android’de uygulamayı açıp bu ekrandan satın alın.',
    'iapAndroidFootnote':
        'Ödemeler Google hesabın üzerinden işlenir.',
    'audienceGrowthScoreTitle': 'Dinleyici gelişim puanı',
    'audienceGrowthScoreBody':
        'Olumlu oran, olumsuz baskı ve yorum hacmine göre hesaplanır; '
        'her «Takipçi Yorum Analizi» çalıştırmasında kayıt tutulur.',
    'growthVsPreviousTitle': 'Önceki rapora göre gelişim',
    'growthVsPreviousEmptyBody':
        'En az iki kez «Takipçi Yorum Analizi» çalıştırdığında; genel puan, '
        'duygu dağılımı ve (varsa) kapak üçlü metrikleri bir önceki kayıtla kıyaslanır.',
    'growthComparedDates': 'Son analiz ({cur}), bir önceki ({prev}) ile kıyaslandı.',
    'growthDeltaOverallScore': 'Genel gelişim puanı',
    'growthDeltaPmScore': 'Olumlu ivme (skor)',
    'growthDeltaRcScore': 'Olumsuz kontrol (skor)',
    'growthDeltaDdScore': 'Örneklem gücü (skor)',
    'growthDeltaSupportivePct': 'Olumlu yorum payı (%)',
    'growthDeltaRiskPct': 'Olumsuz yorum payı (%)',
    'growthCoverTrioLabel': 'Kapak trio (rapor)',
    'growthPerceptionCommunity': 'Topluluk algısı',
    'growthPerceptionTrust': 'Güven',
    'growthPerceptionClarity': 'İçerik netliği',
    'perceptionScoresTitle': 'Algı skorları',
    'perceptionScoresSubtitle':
        'Takipçilerin seni nasıl okuduğuna dair üç ana gösterge.',
    'growthHistoryTitle': 'Gelişim geçmişi',
    'growthHistoryHintMulti':
        'Yeni linklerle havuz büyüdükçe buradan zaman içindeki puan değişimini izleyebilirsin.',
    'growthHistoryHintSingle':
        'Bir sonraki analizde çizgi oluşur; düzenli çalıştırmak trendi netleştirir.',
    'historyCommentsCount': '· {n} yorum',
    'historyOpenReport': 'Rapor ›',
  };
}
