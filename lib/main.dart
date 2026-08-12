import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:device_preview/device_preview.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'design_system/design_system.dart';
import 'services/auth_service.dart' show firebaseAuthUserMessage;
import 'config/backend_config.dart';
import 'config/feature_flags.dart';
import 'config/feedback_reactions.dart';
import 'services/api_session.dart' show ApiSession;
import 'services/railway_backend_sync.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/community_feedback_summary.dart';
import 'models/feedback_entry.dart';
import 'models/feedback_link.dart';
import 'models/audience_score.dart';
import 'models/user_profile.dart';
import 'screens/premium_screen.dart';
import 'screens/settings_screen.dart';
import 'services/report_service.dart';
import 'services/community_summary_store.dart';
import 'widgets/insights/community_summary_v2.dart';
import 'widgets/insights/comment_card.dart';
import 'widgets/profile/profile_header.dart';
import 'widgets/profile/link_history_card.dart';
import 'widgets/splash/feedback_splash_view.dart';
import 'widgets/app_onboarding.dart';
import 'widgets/audience_score_widgets.dart';
import 'widgets/creator_intelligence_report_view.dart';
import 'widgets/creator_survey_section.dart';
import 'theme/app_theme.dart';
import 'theme/feedback_material_theme.dart';
import 'widgets/feedback_link_tile.dart';
import 'widgets/link_validity_countdown.dart';
import 'package:feedback_to_me/utils/reload_stub.dart' if (dart.library.html) 'package:feedback_to_me/utils/reload_web.dart' as reload_util;
import 'package:feedback_to_me/utils/link_create_error.dart';
import 'package:feedback_to_me/utils/unwrap_web_future_error.dart';

const bool _devicePreviewEnabled =
    bool.fromEnvironment('DEVICE_PREVIEW', defaultValue: true);

Widget _withDevicePreview(Widget child) {
  if (!(kIsWeb && _devicePreviewEnabled)) return child;
  return DevicePreview(enabled: true, builder: (_) => child);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    runApp(_withDevicePreview(const _WebSplash()));
    return;
  }
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    initializeAppState();
    final prefs = await SharedPreferences.getInstance();
    L10n.setPrefs(prefs);
    await L10n.loadSavedLocale();
    await ApiSession.instance.loadFromPrefs();
    unawaited(iapService.isStoreAvailable);
    runApp(_withDevicePreview(const FeedbackToMeApp()));
  } catch (e, st) {
    runApp(_withDevicePreview(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF141210),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              '${L10n.boot('bootErrorTitle')}$e\n\n$st',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    )));
  }
}

/// Web: Kısa splash, ardından uygulama. Firebase arka planda.
class _WebSplash extends StatefulWidget {
  const _WebSplash();

  @override
  State<_WebSplash> createState() => _WebSplashState();
}

class _WebSplashState extends State<_WebSplash> {
  bool _go = false;
  bool _timeout = false;

  void _openApp() {
    if (!mounted || _go) return;
    setState(() => _go = true);
  }

  @override
  void initState() {
    super.initState();
    // Firebase hazır olmadan uygulama açılmaz (crash önlenir)
    Future(() async {
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } catch (_) {
        // HTML zaten başlattıysa "already exists" olabilir
      }
      if (Firebase.apps.isNotEmpty) {
        initializeAppState();
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        L10n.setPrefs(prefs);
        await L10n.loadSavedLocale();
      } catch (_) {}
      if (!mounted || _go || _timeout) return;
      setState(() => _go = true);
    });
    // 5 sn sonra hâlâ açılmadıysa hata mesajı göster (Firebase takıldı)
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted || _go) return;
      setState(() => _timeout = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_timeout) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 48, color: Color(0xFFD4AF37)),
                    const SizedBox(height: 24),
                    Text(
                      L10n.boot('webLoadSlowTitle'),
                      style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.boot('webLoadSlowBody'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => reload_util.reloadPage(),
                      icon: const Icon(Icons.refresh),
                      label: Text(L10n.boot('webRefresh')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_go) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                const SizedBox(height: 24),
                Text(L10n.boot('loading'), style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20)),
              ],
            ),
          ),
        ),
      );
    }
    return const FeedbackToMeApp();
  }
}

/// Web: Önce "Yükleniyor..." göster, sonra Firebase + prefs yükle, sonra asıl uygulamaya geç.
class _WebInitWrapper extends StatefulWidget {
  const _WebInitWrapper();

  @override
  State<_WebInitWrapper> createState() => _WebInitWrapperState();
}

class _WebInitWrapperState extends State<_WebInitWrapper> {
  bool _ready = false;
  String? _error;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // En fazla 2 sn bekle; takılırsa "Yenile" göster
      final ok = await Future.any<bool>([
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
            .then((_) => true),
        Future.delayed(const Duration(seconds: 2), () => false),
      ]);
      if (!mounted) return;
      if (ok) {
        if (Firebase.apps.isNotEmpty) {
          initializeAppState();
        }
        SharedPreferences.getInstance().then((prefs) {
          L10n.setPrefs(prefs);
          L10n.loadSavedLocale();
        }).catchError((_) {});
        setState(() => _ready = true);
      } else {
        setState(() => _timedOut = true);
      }
    } catch (e, st) {
      if (mounted) setState(() => _error = '$e\n\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                '${L10n.boot('webErrorLead')}$_error',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    }
    if (_timedOut) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.refresh, size: 48, color: Color(0xFFD4AF37)),
                  const SizedBox(height: 24),
                  Text(
                    L10n.boot('webLoadFailedTitle'),
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.boot('webLoadSlowBody'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    L10n.boot('webLoadF5'),
                    style: TextStyle(color: const Color(0xFFD4AF37), fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                const SizedBox(height: 24),
                Text(
                  L10n.boot('loading'),
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const FeedbackToMeApp();
  }
}

/// İlk açılışta onboarding; tamamlanınca veya atlanınca normal akış.
/// Paylaşılan feedback linki (`.../f/<code>`) ile açıldıysa kodu döndürür.
/// Backend/router değişmez; yalnızca launch URL'i istemci tarafında okunur.
/// Path stratejisi (`/f/x`) ve hash stratejisi (`#/f/x`) desteklenir.
String? _feedbackDeepLinkCode() {
  if (!kIsWeb) return null;
  try {
    String? fromSegments(List<String> segs) {
      final i = segs.indexWhere((s) => s.toLowerCase() == 'f');
      if (i != -1 && i + 1 < segs.length) {
        final c = segs[i + 1].trim();
        return c.isEmpty ? null : c;
      }
      return null;
    }

    final uri = Uri.base;
    final direct = fromSegments(uri.pathSegments);
    if (direct != null) return direct;

    final frag = uri.fragment;
    if (frag.isNotEmpty) {
      final fragUri =
          Uri.tryParse(frag.startsWith('/') ? frag.substring(1) : frag);
      if (fragUri != null) {
        final f = fromSegments(fragUri.pathSegments);
        if (f != null) return f;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

class _AppLaunchGate extends StatefulWidget {
  const _AppLaunchGate();

  @override
  State<_AppLaunchGate> createState() => _AppLaunchGateState();
}

class _AppLaunchGateState extends State<_AppLaunchGate> {
  bool? _onboardingDone;
  String? _deepLinkCode;

  @override
  void initState() {
    super.initState();
    _deepLinkCode = _feedbackDeepLinkCode();
    _load();
  }

  Future<void> _load() async {
    final done = await isOnboardingCompleted();
    if (!mounted) return;
    setState(() => _onboardingDone = done);
  }

  Future<void> _finishOnboarding() async {
    await setOnboardingCompleted();
    if (!mounted) return;
    setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    // Paylaşılan feedback linki: onboarding/giriş atlanır, doğrudan public akış.
    // (Feedback vermek anonim; owner girişi gerekmez.)
    if (_deepLinkCode != null) {
      return FeedbackFormScreen(linkCode: _deepLinkCode);
    }
    if (_onboardingDone == null) {
      return const FeedbackSplashView();
    }
    if (_onboardingDone == false) {
      return AppOnboarding(onFinished: _finishOnboarding);
    }
    return const _AuthGate();
  }
}

/// Auth stream bazen web'de gecikiyor; timeout sonrası açılışı zorla göster.
class _AuthGate extends StatefulWidget {
  const _AuthGate({super.key});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  User? _user;
  bool _timedOut = false;
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      await ApiSession.instance.loadFromPrefs();
      final u = authService.currentUser;
      if (u != null) await ensureRailwayBackendSession(u);
      if (mounted) setState(() {});
    });
    _sub = authService.authStateChanges.listen((user) async {
      if (!mounted) return;
      // Önce senkron güncelle: await Railway/Firestore köprüsü bitene kadar bekleme —
      // aksi halde giriş sonrası LandingScreen eski "çıkışlı" karede kalıyor.
      setState(() => _user = user);
      if (user != null) {
        await ensureRailwayBackendSession(user);
      } else {
        await ApiSession.instance.clear();
      }
      if (mounted) setState(() {});
    });
    // Web'de 1 sn, mobilde 3 sn sonra beklemeden aç
    final timeout = kIsWeb ? const Duration(seconds: 1) : const Duration(seconds: 3);
    Future.delayed(timeout, () {
      if (mounted && !_timedOut) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null || _timedOut) return const LandingScreen();
    return const FeedbackSplashView();
  }
}

/// Koyu mistik arka plan: gece gökyüzü, yumuşak merkez ışığı.
class _DarkMysticalBackground extends StatelessWidget {
  const _DarkMysticalBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1a0a2e),
            Color(0xFF0d0d1a),
            Color(0xFF0a0a0d),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Yumuşak merkez ışığı (kristal / ay etkisi)
          Positioned(
            top: -80,
            left: -80,
            right: -80,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2a1a4a).withOpacity(0.5),
                    const Color(0xFF1a0a2e).withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class FeedbackToMeApp extends StatelessWidget {
  const FeedbackToMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildFeedbackTheme();

    return ValueListenableBuilder<Locale?>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          key: ValueKey(locale?.toString() ?? 'default'),
          title: 'Feedback2Me',
          debugShowCheckedModeBanner: false,
          theme: theme,
          useInheritedMediaQuery: kIsWeb && _devicePreviewEnabled,
          builder: (kIsWeb && _devicePreviewEnabled) ? DevicePreview.appBuilder : null,
          locale: locale ??
              ((kIsWeb && _devicePreviewEnabled) ? DevicePreview.locale(context) : null),
          localeListResolutionCallback: (locales, supported) {
            if (locales == null || locales.isEmpty) {
              return const Locale('en');
            }
            for (final l in locales) {
              if (l.languageCode == 'tr') return const Locale('tr');
              if (l.languageCode == 'en') return const Locale('en');
            }
            return const Locale('en');
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('tr'),
            Locale('en'),
          ],
          home: const _AppLaunchGate(),
        );
      },
    );
  }
}

/// Railway modunda: Firebase girişinden hemen sonra dev-login bitmeden
/// `Navigator.pop` yapılırsa link oluşturma `effectiveDataOwnerId == null` ile düşer.
Future<void> _afterFirebaseLoginCloseSheet(BuildContext context, User? user) async {
  if (!context.mounted || user == null) return;
  final railwayOk = await ensureRailwayBackendSession(user);
  if (!context.mounted) return;
  if (BackendConfig.isRailwayBackendConfigured && !railwayOk) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.get(context, 'railwayLoginSnack')),
        duration: const Duration(seconds: 10),
      ),
    );
  }
  Navigator.of(context).pop(true);
}

/// Giriş: sadece Apple ve Google (ödeme App Store / Play Store'da).
/// Giriş — V2 aydınlık. Auth handler'ları (Google/Apple + misafir) korunur.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _google(BuildContext context) async {
    try {
      final user = await authService.signInWithGoogle();
      if (!context.mounted) return;
      await _afterFirebaseLoginCloseSheet(context, user);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${L10n.get(context, 'loginFailedGoogle')}: ${firebaseAuthUserMessage(e)}'),
        ));
      }
    }
  }

  Future<void> _apple(BuildContext context) async {
    try {
      final user = await authService.signInWithApple();
      if (!context.mounted) return;
      await _afterFirebaseLoginCloseSheet(context, user);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${L10n.get(context, 'loginFailedApple')}: ${firebaseAuthUserMessage(e)}'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthAuth,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'login')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.h),
            Center(
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: AppRadius.rLarge,
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: AppColors.onPrimary, size: 38),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text('Feedback2Me',
                style: AppType.pageTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxl),
            Text(L10n.get(context, 'login'),
                style: AppType.display, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'loginSubtitle'),
                style: AppType.secondary, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxl),
            _AuthProviderButton(
              label: L10n.get(context, 'loginGoogle'),
              icon: Icons.g_mobiledata_rounded,
              onPressed: () => _google(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            _AuthProviderButton(
              label: L10n.get(context, 'loginApple'),
              icon: Icons.apple,
              onPressed: () => _apple(context),
            ),
            const SizedBox(height: AppSpacing.l),
            Center(
              child: FeedbackTextButton(
                label: L10n.get(context, 'continueWithoutLogin'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(L10n.get(context, 'loginPrivacyNote'),
                    style: AppType.caption),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Giriş sağlayıcı butonu (beyaz yüzey + ikon + ortalı etiket).
class _AuthProviderButton extends StatelessWidget {
  const _AuthProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.rMedium,
      child: InkWell(
        borderRadius: AppRadius.rMedium,
        onTap: onPressed,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMedium,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 24),
              const SizedBox(width: 10),
              Text(label,
                  style: AppType.bodyStrong
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Auth her değiştiğinde (giriş/çıkış) yeniden çiz: üst seviye setState gecikse bile
    // "Giriş yapıldı" SnackBar'ı ile çelişen eski UI kalmasın.
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid;
        final isLoggedIn = uid != null;
        if (!isLoggedIn) {
          return _buildLandingBody(
            context,
            isLoggedIn: false,
            profile: null,
            uid: null,
          );
        }
        final dataOwner = effectiveDataOwnerId(uid);
        if (BackendConfig.isRailwayBackendConfigured && dataOwner == null) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: _DarkMysticalBackground(
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.gold),
                      const SizedBox(height: 20),
                      Text(
                        'Sunucu oturumu açılıyor…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return StreamBuilder(
          stream: appData.userProfileStream(dataOwner!),
          builder: (context, profileSnap) {
            return _buildLandingBody(
              context,
              isLoggedIn: true,
              profile: profileSnap.data,
              uid: uid,
            );
          },
        );
      },
    );
  }

  Widget _buildLandingBody(BuildContext context, {required bool isLoggedIn, UserProfile? profile, String? uid}) {
    final isHome = _currentIndex == 0;
    final lang = L10n.languageCodeForApp(context);
    return Theme(
      data: buildFeedbackLightTheme(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: AppSpacing.pageH,
          title: const FeedbackBrandMark(),
          actions: [
            FeedbackLanguageSelector(
              currentCode: lang,
              onSelect: (c) => L10n.setLocale(Locale(c)),
            ),
            const SizedBox(width: AppSpacing.s),
            IconButton(
              icon: const Icon(Icons.settings_outlined,
                  color: AppColors.textSecondary),
              tooltip: L10n.get(context, 'settings'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (ctx) => SettingsScreen(
                      onOpenLogin: (c) => Navigator.of(c).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const LoginScreen()),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (isLoggedIn)
              IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: AppColors.textSecondary),
                tooltip: L10n.get(context, 'logout'),
                onPressed: () async => authService.signOut(),
              )
            else
              IconButton(
                icon: const Icon(Icons.login_rounded,
                    color: AppColors.primary),
                tooltip: L10n.get(context, 'login'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
              ),
            const SizedBox(width: AppSpacing.s),
          ],
        ),
        body: SafeArea(
          child: isHome
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageH, vertical: AppSpacing.l),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxWidthContent),
                      child: _buildHomeContent(isLoggedIn: isLoggedIn, uid: uid),
                    ),
                  ),
                )
              // Profil V2 (aydınlık). Kendi ListView'ı kaydırılır.
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxWidthWide),
                      child: _ProfileTab(profile: profile, uid: uid),
                    ),
                  ),
                ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: AppColors.surface,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_rounded),
                label: L10n.get(context, 'home'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person_rounded),
                label: L10n.get(context, 'profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent({required bool isLoggedIn, String? uid}) {
    final oid = uid != null ? effectiveDataOwnerId(uid) : null;
    if (!isLoggedIn || oid == null) {
      return const _GuestHomeV2();
    }
    return StreamBuilder<List<FeedbackLink>>(
      stream: appData.linksForOwnerStream(oid),
      builder: (context, linksSnap) {
        final links = linksSnap.data ?? [];
        final activeLink = links.cast<FeedbackLink?>().firstWhere(
              (l) => l!.acceptsPublicFeedback,
              orElse: () => null,
            );
        if (activeLink != null) {
          return _ActiveLinkHomeCard(
              link: activeLink, uid: uid!, ownerId: oid, cardPad: 20);
        }
        final latest = links.isNotEmpty ? links.first : null;
        final expired =
            (latest != null && latest.isPastValidWindow) ? latest : null;
        if (expired != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Süresi dolan link final özeti (henüz V2 değil → koyu-sarılı).
              Theme(
                data: buildFeedbackTheme(),
                child: _LinkSummaryCard(
                  key: ValueKey('sum-final-${expired.id}'),
                  link: expired,
                  ownerId: oid,
                  cardPad: 20,
                  isExpired: true,
                  cacheable: true,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              _LoggedInHomeV2(uid: uid!),
            ],
          );
        }
        return _LoggedInHomeV2(uid: uid!);
      },
    );
  }
}

/// Misafir ana ekran V2 — hero + iki aksiyon kartı + "Nasıl çalışır" + güven.
class _GuestHomeV2 extends StatelessWidget {
  const _GuestHomeV2();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.s),
        Text(L10n.get(context, 'homeGreeting'), style: AppType.secondary),
        const SizedBox(height: AppSpacing.xs),
        Text(L10n.get(context, 'homeHeroTitle'), style: AppType.display),
        const SizedBox(height: AppSpacing.s),
        Text(L10n.get(context, 'homeHeroSubtitle'), style: AppType.body),
        const SizedBox(height: AppSpacing.xl),
        FeedbackFeatureCard(
          icon: Icons.link_rounded,
          title: L10n.get(context, 'homeCreateCardTitle'),
          description: L10n.get(context, 'homeCreateCardDesc'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FeedbackFeatureCard(
          icon: Icons.edit_note_rounded,
          iconGradient: const LinearGradient(
              colors: [AppColors.success, Color(0xFF2FB07A)]),
          title: L10n.get(context, 'homeWriteCardTitle'),
          description: L10n.get(context, 'homeWriteCardDesc'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => const FeedbackFormScreen()),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _HowItWorksV2(),
        const SizedBox(height: AppSpacing.l),
        const _TrustRowV2(),
        const SizedBox(height: AppSpacing.m),
      ],
    );
  }
}

/// Girişli kullanıcı, aktif link yokken — V2 karşılama + link oluştur.
class _LoggedInHomeV2 extends StatelessWidget {
  const _LoggedInHomeV2({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.s),
        Text(L10n.get(context, 'homeWelcomeBack'), style: AppType.pageTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(L10n.get(context, 'homeWhatToDo'), style: AppType.secondary),
        const SizedBox(height: AppSpacing.xl),
        FeedbackFeatureCard(
          icon: Icons.add_link_rounded,
          title: L10n.get(context, 'homeCreateCardTitle'),
          description: L10n.get(context, 'homeCreateCardDesc'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => CreateLinkScreenV2(uid: uid)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FeedbackFeatureCard(
          icon: Icons.edit_note_rounded,
          iconGradient: const LinearGradient(
              colors: [AppColors.success, Color(0xFF2FB07A)]),
          title: L10n.get(context, 'homeWriteCardTitle'),
          description: L10n.get(context, 'homeWriteCardDesc'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => const FeedbackFormScreen()),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _HowItWorksV2(),
        const SizedBox(height: AppSpacing.m),
      ],
    );
  }
}

/// "Nasıl çalışır?" 4 adım (V2).
class _HowItWorksV2 extends StatelessWidget {
  const _HowItWorksV2();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.link_rounded, L10n.get(context, 'stepCreate')),
      (Icons.ios_share_rounded, L10n.get(context, 'stepShare')),
      (Icons.forum_rounded, L10n.get(context, 'stepCollect')),
      (Icons.auto_awesome_rounded, L10n.get(context, 'stepSummary')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.get(context, 'howItWorks'), style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: FeedbackStepItem(
                    number: i + 1, icon: steps[i].$1, label: steps[i].$2),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Güven göstergeleri (Anonim · Hızlı · Güvenli).
class _TrustRowV2 extends StatelessWidget {
  const _TrustRowV2();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FeedbackTrustChip(
            label: L10n.get(context, 'trustAnonymous'),
            icon: Icons.visibility_off_rounded),
        FeedbackTrustChip(
            label: L10n.get(context, 'trustFast'), icon: Icons.bolt_rounded),
        FeedbackTrustChip(
            label: L10n.get(context, 'trustSecure'),
            icon: Icons.shield_rounded),
      ],
    );
  }
}

/// Yeni link oluştur — V2 (Demo/Premium bilgi kartları). Mevcut `_createLink`
/// akışını çağırır; tier'a backend karar verir (mantık değişmez).
class CreateLinkScreenV2 extends StatelessWidget {
  const CreateLinkScreenV2({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthAuth,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'createLinkTitle')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'createLinkV2Heading'),
                style: AppType.pageTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(L10n.get(context, 'createLinkV2Sub'), style: AppType.secondary),
            const SizedBox(height: AppSpacing.xl),
            _TierCard(
              icon: Icons.science_rounded,
              title: L10n.get(context, 'tierDemo'),
              priceLabel: L10n.get(context, 'tierFree'),
              features: [
                L10n.get(context, 'tierDemoF1'),
                L10n.get(context, 'tierDemoF2'),
                L10n.get(context, 'tierDemoF3'),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            _TierCard(
              icon: Icons.workspace_premium_rounded,
              title: L10n.get(context, 'tierPremium'),
              priceLabel: L10n.get(context, 'tierPaid'),
              gradient: true,
              features: [
                L10n.get(context, 'tierPremiumF1'),
                L10n.get(context, 'tierPremiumF2'),
                L10n.get(context, 'tierPremiumF3'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FeedbackPrimaryButton(
              label: L10n.get(context, 'createMyLink'),
              trailingArrow: true,
              onPressed: () => _createLink(context, uid),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Demo/Premium tier bilgi kartı.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.icon,
    required this.title,
    required this.priceLabel,
    required this.features,
    this.gradient = false,
  });

  final IconData icon;
  final String title;
  final String priceLabel;
  final List<String> features;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final onGrad = gradient;
    final titleColor = onGrad ? AppColors.onPrimary : AppColors.textPrimary;
    final featColor =
        onGrad ? AppColors.onPrimary.withValues(alpha: 0.92) : AppColors.textPrimary;
    return FeedbackCard(
      gradient: gradient ? AppColors.primaryGradient : null,
      shadow: gradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: onGrad ? AppColors.onPrimary : AppColors.primary,
                  size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: AppType.cardTitle.copyWith(color: titleColor)),
              const Spacer(),
              FeedbackStatusBadge(
                label: priceLabel,
                tone: onGrad ? BadgeTone.neutral : BadgeTone.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 17,
                      color: onGrad ? AppColors.onPrimary : AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(f,
                          style: AppType.secondary.copyWith(color: featColor))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _shareLink(BuildContext context, String url) async {
  try {
    await Share.share(url, subject: L10n.get(context, 'appTitle'));
  } catch (_) {
    Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
      );
    }
  }
}

/// Aktif link kartı: geri sayım + yorum sayısı + BÜYÜK "Paylaş" (asıl eylem) +
/// tek satır canlı önizleme + "süre bitince özet" ipucu.
class _ActiveLinkHomeCard extends StatelessWidget {
  const _ActiveLinkHomeCard({
    required this.link,
    required this.uid,
    required this.ownerId,
    required this.cardPad,
  });

  final FeedbackLink link;
  final String uid;
  final String ownerId;
  final double cardPad;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ana performans kartı (gradient)
        FeedbackCard(
          gradient: AppColors.primaryGradient,
          shadow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FeedbackStatusBadge(
                    label: 'Aktif',
                    tone: BadgeTone.neutral,
                    dot: true,
                  ),
                  const Spacer(),
                  if (link.validUntil != null)
                    LinkValidityCountdown(
                      validUntil: link.validUntil!,
                      compact: true,
                      foreground: AppColors.onPrimary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(L10n.get(context, 'homeLinkActive'),
                  style: AppType.cardTitle.copyWith(color: AppColors.onPrimary)),
              const SizedBox(height: 3),
              Text(
                link.shareUrl,
                style: AppType.secondary
                    .copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.m),
              StreamBuilder<List<FeedbackEntry>>(
                stream: appData.feedbacksForLinkStream(link.id),
                builder: (context, snap) {
                  final count = snap.data?.length ?? 0;
                  return FeedbackMetricCard(
                    value: '$count',
                    label: L10n.get(context, 'feedbacksShort'),
                    icon: Icons.forum_rounded,
                    onSurface: true,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        FeedbackPrimaryButton(
          label: L10n.get(context, 'shareLink'),
          icon: Icons.ios_share_rounded,
          onPressed: () => _shareLink(context, link.shareUrl),
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            Expanded(
              child: FeedbackSecondaryButton(
                label: L10n.get(context, 'copyLink'),
                icon: Icons.copy_rounded,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link.shareUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: FeedbackSecondaryButton(
                label: L10n.get(context, 'newLink'),
                icon: Icons.add_link_rounded,
                onPressed: () => _createLink(context, uid),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        FeedbackCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.get(context, 'homeSummaryHint'),
                  style: AppType.caption),
              const SizedBox(height: AppSpacing.s),
              _LiveSummaryLine(link: link, ownerId: ownerId),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aktif linkte tek satır canlı önizleme ("N kişi — çıkarım"); dokununca tam özet.
class _LiveSummaryLine extends StatefulWidget {
  const _LiveSummaryLine({required this.link, required this.ownerId});

  final FeedbackLink link;
  final String ownerId;

  @override
  State<_LiveSummaryLine> createState() => _LiveSummaryLineState();
}

class _LiveSummaryLineState extends State<_LiveSummaryLine> {
  CommunityFeedbackSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final lang = mounted ? L10n.languageCodeForApp(context) : 'tr';
      final s = await reportService.generateCommunitySummary(
        widget.ownerId,
        linkId: widget.link.id,
        languageCode: lang,
      );
      if (!mounted) return;
      setState(() {
        _summary = s;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AudienceAnalysisScreen(
          ownerId: widget.ownerId,
          linkId: widget.link.id,
          cacheable: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Text(L10n.get(context, 'expiredSummaryPreparing'),
              style: AppType.caption),
        ],
      );
    }
    final s = _summary;
    if (s == null || s.feedbackCount == 0) {
      return Row(
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(L10n.get(context, 'homeNoFeedbackYet'),
                style: AppType.secondary),
          ),
        ],
      );
    }
    final line = s.headline.isNotEmpty
        ? s.headline
        : (s.mostMentioned.isNotEmpty
            ? s.mostMentioned.first
            : L10n.get(context, 'liveSummaryTitle'));
    return InkWell(
      onTap: _open,
      borderRadius: AppRadius.rSmall,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong),
            ),
            const SizedBox(width: 6),
            Text(L10n.get(context, 'expiredSummaryOpen'),
                style: AppType.caption.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// Link özet kartı: aktifken "canlı özet" (yorum geldikçe), süre dolunca "final özet".
/// Kısa çıkarımları (istek + gözlem) üretir; tam özete "Özeti gör" ile götürür.
class _LinkSummaryCard extends StatefulWidget {
  const _LinkSummaryCard({
    super.key,
    required this.link,
    required this.ownerId,
    required this.cardPad,
    required this.isExpired,
    this.cacheable = true,
  });

  final FeedbackLink link;
  final String ownerId;
  final double cardPad;

  /// true: link süresi doldu → "final özet". false: aktif link → "canlı özet".
  final bool isExpired;

  /// true: özet cihazda önbelleğe alınır (final özet — bir kez üret).
  /// false: her seferinde taze üret (canlı özet, yorum geldikçe).
  final bool cacheable;

  @override
  State<_LinkSummaryCard> createState() => _LinkSummaryCardState();
}

class _LinkSummaryCardState extends State<_LinkSummaryCard> {
  CommunityFeedbackSummary? _summary;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      CommunityFeedbackSummary? summary = widget.cacheable
          ? await CommunitySummaryStore.instance.load(widget.link.id)
          : null;
      if (summary == null) {
        final lang = mounted ? L10n.languageCodeForApp(context) : 'tr';
        summary = await reportService.generateCommunitySummary(
          widget.ownerId,
          linkId: widget.link.id,
          languageCode: lang,
        );
        if (widget.cacheable) {
          await CommunitySummaryStore.instance.save(widget.link.id, summary);
        }
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _openSummary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AudienceAnalysisScreen(
          ownerId: widget.ownerId,
          linkId: widget.link.id,
          cacheable: widget.cacheable,
        ),
      ),
    );
  }

  String _preview(BuildContext context, CommunityFeedbackSummary s) {
    if (s.headline.isNotEmpty) return s.headline;
    if (s.shortSummary.isNotEmpty) return s.shortSummary;
    return L10n.get(context, 'summaryPreviewNone')
        .replaceAll('{count}', '${s.feedbackCount}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Canlı özet + henüz yorum yok → kartı gizle (aktif link kartı zaten sayaç gösterir).
    final s = _summary;
    if (!_loading &&
        !_error &&
        s != null &&
        !widget.isExpired &&
        s.feedbackCount == 0) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: EdgeInsets.all(widget.cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.isExpired
                      ? Icons.timer_off_outlined
                      : Icons.insights_outlined,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10n.get(
                      context,
                      widget.isExpired
                          ? 'expiredSummaryTitle'
                          : 'liveSummaryTitle',
                    ),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: L10n.get(context, 'retry'),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      L10n.get(context, 'expiredSummaryPreparing'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              )
            else if (_error)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.get(context, 'expiredSummaryError'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(L10n.get(context, 'retry')),
                  ),
                ],
              )
            else ...[
              Text(
                _preview(context, _summary!),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openSummary,
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: Text(L10n.get(context, 'expiredSummaryOpen')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  void _continueToDashboard() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final uid = authService.uid;
    if (uid == null) return;

    final handle = _handleController.text.trim().isEmpty
        ? null
        : _handleController.text.trim();
    final profile = UserProfile(
      uid: effectiveDataOwnerId(uid) ?? uid,
      displayName: name,
      handle: handle,
      createdAt: DateTime.now(),
    );
    await appData.setUserProfile(uid, profile);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          uid: uid,
          displayName: name,
          handle: handle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.get(context, 'createProfile')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10n.get(context, 'createProfileSubtitle'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'nameLabel'),
                      hintText: L10n.get(context, 'nameHint'),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _handleController,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'handleLabel'),
                      hintText: L10n.get(context, 'handleHint'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _continueToDashboard,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      L10n.get(context, 'continueToPremium'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.get(context, 'createProfileNote'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Flutter Web’de Firestore [runTransaction] içindeki [StateError] bazen JS
/// sarmalayıcısına dönüşür; [e is StateError] false kalır.
bool _errorMeansLinkRequiresCredit(Object e) {
  if (e is StateError) return e.message == 'link_requires_credit';
  return e.toString().contains('link_requires_credit');
}

bool _errorMeansLinkCreateAuthMismatch(Object e) {
  if (e is StateError) return e.message == 'link_create_auth_mismatch';
  return e.toString().contains('link_create_auth_mismatch');
}

Future<void> _createLink(BuildContext context, String uid) async {
  var owner = effectiveDataOwnerId(uid);
  if (owner == null && BackendConfig.isRailwayBackendConfigured) {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      await ensureRailwayBackendSession(u);
      owner = effectiveDataOwnerId(uid);
    }
  }
  if (owner == null) {
    if (!context.mounted) return;
    final msg = BackendConfig.isRailwayBackendConfigured
        ? '${L10n.get(context, 'linkCreateFailed')} (Sunucu oturumu yok: girişten sonra birkaç saniye bekleyip tekrar deneyin veya DEV_AUTH_SECRET / e-posta kontrol edin.)'
        : L10n.get(context, 'linkCreateFailed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    return;
  }

  try {
    final existingLinks = await appData.getLinksForOwner(owner);
    final hasActiveLink = existingLinks.any((l) => l.acceptsPublicFeedback);
    if (hasActiveLink && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.get(ctx, 'activeLinkExistsTitle')),
          content: Text(L10n.get(ctx, 'activeLinkExistsBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L10n.get(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L10n.get(ctx, 'activeLinkExistsConfirm')),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }
  } catch (_) {}

  if (!BackendConfig.isRailwayBackendConfigured) {
    final cu = FirebaseAuth.instance.currentUser;
    if (cu == null || cu.uid != owner) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'linkCreateAuthMismatch'))),
      );
      return;
    }
  }

  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (_) {}
  }

  Object? err;
  StackTrace? errStack;
  FeedbackLink? link;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (kIsWeb && attempt > 0) {
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      } catch (_) {}
    }
    try {
      link = await appData.createLink(owner);
      err = null;
      errStack = null;
      break;
    } catch (e, st) {
      err = e;
      errStack = st;
      final r = linkCreateErrorText(e);
      final perm = r.contains('permission-denied') ||
          r.toLowerCase().contains('permission denied');
      if (kIsWeb && perm && attempt < 2) {
        continue;
      }
      break;
    }
  }

  if (err != null) {
    final e = err;
    final st = errStack;
    final root = unwrapWebFutureError(e) ?? e;
    final readable = linkCreateErrorText(e);
    if (kDebugMode) {
      debugPrint('createLink failed: $readable');
      debugPrint('$st');
    }
    if (!context.mounted) return;
    if (_errorMeansLinkRequiresCredit(root) ||
        readable.contains('link_requires_credit')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.get(context, 'linkRequiresCredit')),
          action: SnackBarAction(
            label: L10n.get(context, 'creditSheetOpenPremium'),
            onPressed: () async {
              final purchased = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const PremiumScreen(),
                ),
              );
              if (purchased == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(L10n.get(context, 'creditPurchasedCreateLink')),
                    action: SnackBarAction(
                      label: L10n.get(context, 'newLink'),
                      onPressed: () => _createLink(context, uid),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
      return;
    }
    if (_errorMeansLinkCreateAuthMismatch(root) ||
        readable.contains('link_create_auth_mismatch')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'linkCreateAuthMismatch'))),
      );
      return;
    }
    final detail = linkCreateErrorText(root);
    final looksInterop = detail.contains('converted Future') ||
        detail.contains('boxed error') ||
        detail == '[object Object]' ||
        detail == '[object Error]';
    var msg = looksInterop
        ? L10n.get(context, 'linkCreateFailedInterop')
        : '${L10n.get(context, 'linkCreateFailed')}: $detail';
    if (detail.contains('permission-denied') ||
        detail.toLowerCase().contains('permission denied')) {
      msg = '$msg\n${L10n.get(context, 'linkCreateFirestoreDeployHint')}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 8),
      ),
    );
    return;
  }

  final createdLink = link;
  if (createdLink == null || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: createdLink.shareUrl));
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CreatedLinkScreen(link: createdLink),
    ),
  );
}

class CreatedLinkScreen extends StatelessWidget {
  const CreatedLinkScreen({super.key, required this.link});

  final FeedbackLink link;

  @override
  Widget build(BuildContext context) {
    final demo = link.isDemoTier;
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'yourLinks')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.l),
            Center(
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.onPrimary, size: 40),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(L10n.get(context, 'linkCreatedV2Title'),
                style: AppType.display, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'linkCreatedV2Sub'),
                style: AppType.secondary, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xl),
            FeedbackCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FeedbackStatusBadge(
                        label: demo
                            ? L10n.get(context, 'tierDemo')
                            : L10n.get(context, 'tierPremium'),
                        tone: demo ? BadgeTone.neutral : BadgeTone.primary,
                      ),
                      const Spacer(),
                      Icon(
                          demo
                              ? Icons.science_rounded
                              : Icons.workspace_premium_rounded,
                          color: AppColors.primary,
                          size: 20),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(link.shareUrl, style: AppType.bodyStrong),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _tierInfo(
                          Icons.schedule_rounded,
                          demo
                              ? L10n.get(context, 'tierDemoF1')
                              : L10n.get(context, 'tierPremiumF1')),
                      const SizedBox(width: AppSpacing.m),
                      _tierInfo(
                          Icons.forum_rounded,
                          demo
                              ? L10n.get(context, 'tierDemoF2')
                              : L10n.get(context, 'tierPremiumF2')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            FeedbackPrimaryButton(
              label: L10n.get(context, 'shareLink'),
              icon: Icons.ios_share_rounded,
              onPressed: () => Share.share(link.shareUrl),
            ),
            const SizedBox(height: AppSpacing.s),
            FeedbackSecondaryButton(
              label: L10n.get(context, 'copyLink'),
              icon: Icons.copy_rounded,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link.shareUrl));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
                );
              },
            ),
            if (demo) ...[
              const SizedBox(height: AppSpacing.l),
              FeedbackCard(
                color: AppColors.primarySoft,
                shadow: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.get(context, 'createdLinkPremiumPitch'),
                        style: AppType.secondary),
                    const SizedBox(height: AppSpacing.sm),
                    FeedbackSecondaryButton(
                      label: L10n.get(context, 'createdLinkOpenPremium'),
                      icon: Icons.workspace_premium_rounded,
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                            builder: (_) => const PremiumScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _tierInfo(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(label, style: AppType.caption),
      ],
    );
  }
}

Future<void> _createReport(BuildContext context, String linkId) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final report = await reportService.generateReport(
      linkId,
      languageCode: L10n.languageCodeForApp(context),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(L10n.get(context, 'reportSummary')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${report.feedbackCount} ${L10n.get(context, 'feedbackCollected')}'),
                if (report.sentimentLine != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    report.sentimentLine!,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
                if (report.summary != null) ...[
                  const SizedBox(height: 12),
                  Text(report.summary!),
                ],
                if (report.narrativeInsight != null &&
                    report.narrativeInsight!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Derin analiz',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report.narrativeInsight!,
                    style: const TextStyle(height: 1.4),
                  ),
                ],
                if (report.prioritizedActions != null &&
                    report.prioritizedActions!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Öncelikli adımlar',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  ...report.prioritizedActions!.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $a', style: const TextStyle(fontSize: 13, height: 1.35)),
                    ),
                  ),
                ],
                if (report.bullets != null && report.bullets!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Örnek alıntılar',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  ...report.bullets!.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $b', style: const TextStyle(fontSize: 12)),
                  )),
                ],
                const SizedBox(height: 8),
                Text(
                  L10n.get(context, 'reportMoreDetail'),
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.get(context, 'close')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ReportAnalysisScreen(),
                  ),
                );
              },
              child: Text(L10n.get(context, 'goToAnalysis')),
            ),
          ],
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${L10n.get(context, 'reportFailed')}: $e')),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.uid,
    this.displayName,
    this.handle,
  });

  final String uid;
  final String? displayName;
  final String? handle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameText = displayName ?? L10n.get(context, 'premiumUser');
    final handleText = handle;
    final dataOwner = effectiveDataOwnerId(uid);
    if (BackendConfig.isRailwayBackendConfigured && dataOwner == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.get(context, 'dashboardTitle')),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      );
    }
    final oid = dataOwner!;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.get(context, 'dashboardTitle')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.get(context, 'profile'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              child: Text(
                                nameText.isNotEmpty
                                    ? nameText[0].toUpperCase()
                                    : 'F',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nameText,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  if (handleText != null &&
                                      handleText.isNotEmpty)
                                    Text(
                                      handleText,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    L10n.get(context, 'premiumActive'),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.greenAccent),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      L10n.get(context, 'yourLinks'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<FeedbackLink>>(
                      stream: appData.linksForOwnerStream(oid),
                      builder: (context, snap) {
                        final links = snap.data ?? [];
                        final firstLink = links.isNotEmpty ? links.first : null;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.get(context, 'activeLink'),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                if (firstLink != null)
                                  FeedbackLinkTile(
                                    link: firstLink,
                                    onAnalyze: (lid) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AudienceAnalysisScreen(
                                            ownerId: effectiveDataOwnerId(uid) ?? uid,
                                            linkId: lid,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                else
                                  Text(
                                    L10n.get(context, 'noLinksYet'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () => _createLink(context, uid),
                                      icon: const Icon(Icons.add_link),
                                      label: Text(L10n.get(context, 'newLink')),
                                    ),
                                    const SizedBox(width: 8),
                                    if (firstLink != null) ...[
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: firstLink.shareUrl),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(L10n.get(context, 'linkCopied'))),
                                          );
                                        },
                                        icon: const Icon(Icons.share_outlined),
                                        label: Text(L10n.get(context, 'shareLink')),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.tonalIcon(
                                        onPressed: () => _createReport(context, firstLink.id),
                                        icon: const Icon(Icons.analytics_outlined),
                                        label: Text(L10n.get(context, 'createReport')),
                                      ),
                                    ],
                                  ],
                                ),
                                if (links.length > 1) ...[
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  ...links.skip(1).map(
                                        (l) => Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: FeedbackLinkTile(
                                            link: l,
                                            onAnalyze: (lid) {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => AudienceAnalysisScreen(
                                                    ownerId: effectiveDataOwnerId(uid) ?? uid,
                                                    linkId: lid,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  L10n.get(context, 'linksInfo'),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      L10n.get(context, 'campaigns'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '2–3 haftalık feedback dönemleri',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${L10n.get(context, 'comparePeriodsExampleTitle')}\n'
                              '${L10n.get(context, 'comparePeriodsExampleBody')}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.analytics_outlined),
                              label: Text(L10n.get(context, 'viewSampleChangeReport')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({this.profile, this.uid});

  final UserProfile? profile;
  final String? uid;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}


class _ProfileTabState extends State<_ProfileTab> {
  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final uid = widget.uid;
    final oid = uid != null ? effectiveDataOwnerId(uid) : null;

    if (uid == null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
        children: [
          const SizedBox(height: AppSpacing.h),
          FeedbackEmptyState(
            icon: Icons.person_outline_rounded,
            title: L10n.get(context, 'profileV2SignedOutTitle'),
            message: L10n.get(context, 'profileV2SignedOutBody'),
            ctaLabel: L10n.get(context, 'login'),
            onCta: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      );
    }
    if (oid == null) {
      return const Center(child: FeedbackLoadingState());
    }

    return StreamBuilder<List<FeedbackLink>>(
      stream: appData.linksForOwnerStream(oid),
      builder: (context, snap) {
        final hasError = snap.hasError;
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final links = snap.data ?? const <FeedbackLink>[];
        final activeCount = links.where((l) => l.acceptsPublicFeedback).length;

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
          children: [
            FeedbackProfileHeader(profile: profile),
            const SizedBox(height: AppSpacing.l),
            _ProfileActions(
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) => SettingsScreen(
                    onOpenLogin: (c) => Navigator.of(c).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen()),
                    ),
                    developerToolsBuilder: kDebugMode
                        ? (dctx) => DeveloperToolsScreen(ownerId: oid)
                        : null,
                  ),
                ),
              ),
              onReports: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ReportAnalysisScreen()),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            if (!hasError) ...[
              _ProfileMetrics(
                  ownerId: oid,
                  totalLinks: links.length,
                  activeLinks: activeCount),
              const SizedBox(height: AppSpacing.l),
            ],
            Text(L10n.get(context, 'profileV2Links'),
                style: AppType.sectionTitle),
            const SizedBox(height: AppSpacing.m),
            if (hasError)
              FeedbackErrorState(
                message: L10n.get(context, 'profileV2LinksError'),
                retryLabel: L10n.get(context, 'retry'),
                onRetry: () => setState(() {}),
              )
            else if (loading) ...[
              const _LinkSkeleton(),
              const SizedBox(height: AppSpacing.sm),
              const _LinkSkeleton(),
            ] else if (links.isEmpty)
              FeedbackEmptyState(
                icon: Icons.link_rounded,
                title: L10n.get(context, 'profileV2NoLinksTitle'),
                message: L10n.get(context, 'profileV2NoLinksBody'),
                ctaLabel: L10n.get(context, 'createLinkTitle'),
                onCta: () => _createLink(context, uid),
              )
            else
              ...links.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LinkHistoryTile(link: l, ownerId: oid),
                  )),
            const SizedBox(height: AppSpacing.l),
          ],
        );
      },
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({required this.onSettings, required this.onReports});
  final VoidCallback onSettings;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FeedbackSecondaryButton(
            label: L10n.get(context, 'settings'),
            icon: Icons.settings_outlined,
            onPressed: onSettings,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: FeedbackSecondaryButton(
            label: L10n.get(context, 'profileV2Reports'),
            icon: Icons.trending_up_rounded,
            onPressed: onReports,
          ),
        ),
      ],
    );
  }
}

class _ProfileMetrics extends StatefulWidget {
  const _ProfileMetrics({
    required this.ownerId,
    required this.totalLinks,
    required this.activeLinks,
  });
  final String ownerId;
  final int totalLinks;
  final int activeLinks;

  @override
  State<_ProfileMetrics> createState() => _ProfileMetricsState();
}

class _ProfileMetricsState extends State<_ProfileMetrics> {
  int? _totalFeedback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ProfileMetrics old) {
    super.didUpdateWidget(old);
    if (old.ownerId != widget.ownerId) _load();
  }

  Future<void> _load() async {
    try {
      final n = await appData.countAllFeedbacksForOwner(widget.ownerId);
      if (mounted) setState(() => _totalFeedback = n);
    } catch (_) {
      // Sessiz geç — metrik "…" kalır, ekranı bloklamaz.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FeedbackMetricCard(
            value: '${widget.totalLinks}',
            label: L10n.get(context, 'profileV2TotalLinks'),
            icon: Icons.link_rounded,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FeedbackMetricCard(
            value: _totalFeedback?.toString() ?? '…',
            label: L10n.get(context, 'profileV2TotalFeedback'),
            icon: Icons.forum_rounded,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FeedbackMetricCard(
            value: '${widget.activeLinks}',
            label: L10n.get(context, 'profileV2ActiveLinks'),
            icon: Icons.bolt_rounded,
          ),
        ),
      ],
    );
  }
}

/// Link kartı — feedback sayısını bir kez çeker (kalıcı listener değil).
class _LinkHistoryTile extends StatefulWidget {
  const _LinkHistoryTile({required this.link, required this.ownerId});
  final FeedbackLink link;
  final String ownerId;

  @override
  State<_LinkHistoryTile> createState() => _LinkHistoryTileState();
}

class _LinkHistoryTileState extends State<_LinkHistoryTile> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await appData.feedbackCountForLink(widget.link.id);
      if (mounted) setState(() => _count = n);
    } catch (_) {}
  }

  void _openSummary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AudienceAnalysisScreen(
          ownerId: widget.ownerId,
          linkId: widget.link.id,
          cacheable: true,
        ),
      ),
    );
  }

  void _openComments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AllCommentsScreen(
          linkId: widget.link.id,
          title: L10n.get(context, 'commentsTitle'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return LinkHistoryCard(
      link: link,
      feedbackCount: _count,
      onShare: () => _shareLink(context, link.shareUrl),
      onCopy: () async {
        await Clipboard.setData(ClipboardData(text: link.shareUrl));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
        );
      },
      onSummary: _openSummary,
      onComments: _openComments,
      onTap: link.acceptsPublicFeedback ? null : _openSummary,
    );
  }
}

class _LinkSkeleton extends StatelessWidget {
  const _LinkSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(90, 20),
          const SizedBox(height: 14),
          bar(160, 14),
          const SizedBox(height: 10),
          bar(double.infinity, 12),
          const SizedBox(height: 16),
          bar(double.infinity, 48),
        ],
      ),
    );
  }
}

/// Debug-only geliştirici araçları (örnek/bot yorum tohumlama + havuz).
/// Yalnızca kDebugMode'da profilden erişilir; release widget tree'sinde YOK.
class DeveloperToolsScreen extends StatefulWidget {
  const DeveloperToolsScreen({super.key, required this.ownerId});
  final String ownerId;

  @override
  State<DeveloperToolsScreen> createState() => _DeveloperToolsScreenState();
}

class _DeveloperToolsScreenState extends State<DeveloperToolsScreen> {
  int _refreshTick = 0;
  int _bulkTarget = 1000;

  void _refreshPool() => setState(() => _refreshTick++);

  Future<void> _runBulkSeed() async {
    final ownerId = widget.ownerId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.get(context, 'bulkTestDataTitle')),
        content: Text(L10n.get(context, 'bulkTestDataBody')
            .replaceAll('{n}', '$_bulkTarget')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L10n.get(context, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L10n.get(context, 'yes'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(L10n.get(context, 'commentsWriting')),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final written = await appData.seedBulkDemoFeedbacksForOwner(ownerId,
          count: _bulkTarget);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (written == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'snackCreateLinkFirst'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.get(context, 'snackCommentsAdded')
                  .replaceAll('{n}', '$written'))),
        );
        _refreshPool();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                L10n.get(context, 'errorGeneric').replaceAll('{e}', '$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Debug aracı — koyu tema (V2 kapsamı dışı).
    return Theme(
      data: buildFeedbackTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Developer Tools')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(L10n.get(context, 'devSeedTitle'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(L10n.get(context, 'devSeedBody'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  try {
                    final n = await appData
                        .seedDemoFeedbacksForOwner(widget.ownerId);
                    if (!mounted) return;
                    if (n == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              L10n.get(context, 'snackCreateLinkFirstLong'))));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              L10n.get(context, 'snackSampleCommentsAdded')
                                  .replaceAll('{n}', '$n'))));
                      _refreshPool();
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(L10n.get(context, 'snackCouldNotAdd')
                            .replaceAll('{e}', '$e'))));
                  }
                },
                icon: const Icon(Icons.science_outlined),
                label: Text(L10n.get(context, 'devSeed12')),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('Toplu bot yorumları',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  DropdownButton<int>(
                    value: _bulkTarget,
                    items: const [
                      DropdownMenuItem(value: 100, child: Text('100')),
                      DropdownMenuItem(value: 250, child: Text('250')),
                      DropdownMenuItem(value: 500, child: Text('500')),
                      DropdownMenuItem(value: 1000, child: Text('1000')),
                      DropdownMenuItem(value: 2000, child: Text('2000')),
                      DropdownMenuItem(value: 3000, child: Text('3000')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _bulkTarget = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _runBulkSeed,
                icon: const Icon(Icons.smart_toy_outlined),
                label: Text(L10n.get(context, 'bulkBotGenerate')
                    .replaceAll('{n}', '$_bulkTarget')),
              ),
              const SizedBox(height: 24),
              _FeedbackPoolCard(
                ownerId: widget.ownerId,
                refreshTick: _refreshTick,
                onRefresh: _refreshPool,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackPoolCard extends StatelessWidget {
  const _FeedbackPoolCard({
    required this.ownerId,
    required this.refreshTick,
    required this.onRefresh,
  });

  final String ownerId;
  final int refreshTick;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<FeedbackLink>>(
      stream: appData.linksForOwnerStream(ownerId),
      builder: (context, linksSnap) {
        final links = linksSnap.data ?? [];
        final activeLink = links.cast<FeedbackLink?>().firstWhere(
              (l) => l!.acceptsPublicFeedback,
              orElse: () => null,
            );
        final expiredWithComments = links.cast<FeedbackLink?>().firstWhere(
              (l) => l!.isPastValidWindow && !l.isDemoTier,
              orElse: () => null,
            );

        if (activeLink != null) {
          return _ActiveLinkPoolContent(
            theme: theme,
            ownerId: ownerId,
            link: activeLink,
            onRefresh: onRefresh,
          );
        }

        if (expiredWithComments != null) {
          return _ExpiredLinkPoolContent(
            theme: theme,
            ownerId: ownerId,
            link: expiredWithComments,
            onRefresh: onRefresh,
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.get(context, 'poolNoActiveLink'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: L10n.get(context, 'refreshTooltip'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.get(context, 'poolNoActiveLinkHint'),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActiveLinkPoolContent extends StatelessWidget {
  const _ActiveLinkPoolContent({
    required this.theme,
    required this.ownerId,
    required this.link,
    required this.onRefresh,
  });

  final ThemeData theme;
  final String ownerId;
  final FeedbackLink link;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedbackEntry>>(
      stream: appData.feedbacksForLinkStream(link.id),
      builder: (context, snap) {
        final entries = snap.data ?? const <FeedbackEntry>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.get(context, 'poolActiveLink')
                            .replaceAll('{n}', '${entries.length}'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: L10n.get(context, 'refreshTooltip'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snap.connectionState == ConnectionState.waiting && entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (entries.isEmpty)
                  Text(
                    L10n.get(context, 'poolEmptyHint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  )
                else ...[
                  ...entries.take(10).map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '• ${e.textRaw}\n'
                        '  ${e.relation?.trim().isNotEmpty == true ? e.relation! : L10n.get(context, 'relationUnknown')} · ${_moodLabel(context, e.mood)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ),
                  if (entries.length > 10)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _AllCommentsScreen(
                              linkId: link.id,
                              title: L10n.get(context, 'allCommentsTitle'),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: Text(
                        L10n.get(context, 'viewAllComments')
                            .replaceAll('{n}', '${entries.length}'),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Text(
                  L10n.get(context, 'poolCollecting'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade300,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExpiredLinkPoolContent extends StatelessWidget {
  const _ExpiredLinkPoolContent({
    required this.theme,
    required this.ownerId,
    required this.link,
    required this.onRefresh,
  });

  final ThemeData theme;
  final String ownerId;
  final FeedbackLink link;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: appData.feedbackCountForLink(link.id),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.get(context, 'poolExpiredLink')
                            .replaceAll('{n}', '$count'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: L10n.get(context, 'refreshTooltip'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (count > 0) ...[
                  Text(
                    L10n.get(context, 'poolExpiredReady'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AudienceAnalysisScreen(
                            ownerId: ownerId,
                            linkId: link.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(L10n.get(context, 'aiAudienceAnalysisRun')),
                  ),
                ] else
                  Text(
                    L10n.get(context, 'poolExpiredNoComments'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllCommentsScreen extends StatefulWidget {
  const _AllCommentsScreen({required this.linkId, required this.title});

  final String linkId;
  final String title;

  @override
  State<_AllCommentsScreen> createState() => _AllCommentsScreenState();
}

class _AllCommentsScreenState extends State<_AllCommentsScreen> {
  int _filter = 0; // 0=Tümü, 1=Olumlu, 2=Nötr, 3=Geliştirmeli

  bool _match(FeedbackEntry e) {
    switch (_filter) {
      case 1:
        return e.mood == 1;
      case 2:
        return e.mood == 0 || e.mood == null;
      case 3:
        return e.mood == -1;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthComments,
      appBar: feedbackAppBar(context, title: widget.title),
      body: StreamBuilder<List<FeedbackEntry>>(
        stream: appData.feedbacksForLinkStream(widget.linkId),
        builder: (context, snap) {
          final all = snap.data ?? const <FeedbackEntry>[];
          if (snap.connectionState == ConnectionState.waiting && all.isEmpty) {
            return FeedbackLoadingState(message: L10n.get(context, 'loading'));
          }
          if (all.isEmpty) {
            return FeedbackEmptyState(
              icon: Icons.forum_outlined,
              title: L10n.get(context, 'commentsEmptyTitle'),
              message: L10n.get(context, 'commentsEmptyBody'),
            );
          }
          // Sıralama backend'den geldiği gibi korunur (newest-first).
          final filtered = all.where(_match).toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.m, bottom: AppSpacing.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.get(context, 'commentsCount')
                            .replaceFirst('{n}', '${all.length}'),
                        style: AppType.secondary,
                      ),
                      const SizedBox(height: AppSpacing.m),
                      _CommentFilterBar(
                        current: _filter,
                        onSelect: (i) => setState(() => _filter = i),
                      ),
                      const SizedBox(height: AppSpacing.s),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: FeedbackEmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: L10n.get(context, 'commentsFilterEmpty'),
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) =>
                      FeedbackCommentCard(entry: filtered[i]),
                ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.l)),
            ],
          );
        },
      ),
    );
  }
}

/// Yorum filtreleri (client-side; backend query/sıralama değişmez).
class _CommentFilterBar extends StatelessWidget {
  const _CommentFilterBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = [
      L10n.get(context, 'filterAll'),
      L10n.get(context, 'moodPositive'),
      L10n.get(context, 'moodNeutral'),
      L10n.get(context, 'insightNeedsWork'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _pill(labels[i], current == i, () => onSelect(i)),
            if (i < labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: AppRadius.rPill,
        child: InkWell(
          borderRadius: AppRadius.rPill,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: AppRadius.rPill,
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border),
            ),
            child: Text(label,
                style: AppType.secondary.copyWith(
                    color:
                        selected ? AppColors.onPrimary : AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

String _moodLabel(BuildContext context, int? mood) {
  if (mood == 1) return L10n.get(context, 'moodPositive');
  if (mood == -1) return L10n.get(context, 'moodNegative');
  return L10n.get(context, 'moodNeutral');
}

IconData _audienceLoadPhaseIcon(AudienceAnalysisLoadPhase phase) {
  switch (phase) {
    case AudienceAnalysisLoadPhase.fetchingComments:
      return Icons.cloud_download_rounded;
    case AudienceAnalysisLoadPhase.scanningComments:
      return Icons.insights_rounded;
    case AudienceAnalysisLoadPhase.aiChunks:
      return Icons.auto_awesome;
    case AudienceAnalysisLoadPhase.aiMerge:
      return Icons.merge_type_rounded;
    case AudienceAnalysisLoadPhase.buildingHeuristicReport:
      return Icons.article_rounded;
  }
}

/// Takipçi analizi uzun sürdüğünde aşama metni + isteğe bağlı parça ilerlemesi.
class _AudienceAnalysisLoadingPanel extends StatelessWidget {
  const _AudienceAnalysisLoadingPanel({required this.state});

  final AudienceAnalysisLoadState? state;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    final phase = state?.phase ?? AudienceAnalysisLoadPhase.fetchingComments;
    final title =
        state?.title ?? L10n.get(context, 'audienceLoadingTitle');
    final subtitle =
        state?.subtitle ?? L10n.get(context, 'audienceLoadingSubtitle');
    final idx = state?.stepIndex;
    final tot = state?.stepTotal;
    final hasChunkProgress = idx != null && tot != null && tot > 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF252320),
                  const Color(0xFF141210),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Icon(
                      _audienceLoadPhaseIcon(phase),
                      color: accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 22),
                  if (hasChunkProgress) ...[
                    Row(
                      children: [
                        Text(
                          'Parça $idx / $tot',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${((idx * 100) / tot).round()}%',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white54,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: idx / tot,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        color: accent,
                      ),
                    ),
                  ] else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: const LinearProgressIndicator(
                        minHeight: 7,
                        backgroundColor: Color(0x22FFFFFF),
                        color: accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_clock_rounded, size: 16, color: Colors.white.withValues(alpha: 0.45)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Ekranı açık tutun · uygulama arka planda uzun süre beklerse işlem yarıda kalabilir',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.white38,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Firestore’daki bir anlık görüntüden tam takipçi raporunu salt okunur açar.
class SavedAudienceReportScreen extends StatelessWidget {
  const SavedAudienceReportScreen({
    super.key,
    required this.ownerId,
    required this.snapshot,
    this.previousSnapshot,
  });

  final String ownerId;
  final AudienceScoreSnapshot snapshot;
  final AudienceScoreSnapshot? previousSnapshot;

  @override
  Widget build(BuildContext context) {
    final delta = previousSnapshot != null
        ? snapshot.scores.overall - previousSnapshot!.scores.overall
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.get(context, 'savedReportAppBar'))),
      body: SafeArea(
        child: FutureBuilder<AudienceScoreSnapshot>(
          future: appData
              .loadAudienceScoreSnapshotWithBody(ownerId, snapshot.id)
              .then((v) => v ?? snapshot),
          builder: (context, asyncSnap) {
            if (asyncSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (asyncSnap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    L10n.get(context, 'reportLoadFailed')
                        .replaceAll('{e}', '${asyncSnap.error}'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final merged = asyncSnap.data ?? snapshot;
            final result = AudienceAnalysisResult.fromHistorySnapshot(merged);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: CreatorIntelligenceReportView(
                result: result,
                deltaFromPrevious: delta,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paylaşım için kısa özet kartı (gelişim ekranı).
class _ReportSharePreviewCard extends StatelessWidget {
  const _ReportSharePreviewCard({required this.history});

  final List<AudienceScoreSnapshot> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final latest = history.first;
    final summary = (latest.executiveSummary != null && latest.executiveSummary!.trim().isNotEmpty)
        ? latest.executiveSummary!.trim()
        : (latest.creatorReport != null && latest.creatorReport!.executiveSummary.trim().isNotEmpty)
            ? latest.creatorReport!.executiveSummary.trim()
            : null;

    return Card(
      color: const Color(0xFF1C1917),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: const Color(0xFFD4AF37).withOpacity(0.2),
                border: Border.all(color: const Color(0xFFD4AF37)),
              ),
              child: Text(
                L10n.get(context, 'growthSummaryBadge'),
                style: const TextStyle(
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              L10n.get(context, 'currentScoreLine')
                  .replaceAll('{score}', '${latest.scores.overall}')
                  .replaceAll('{count}', '${latest.feedbackCount}'),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (history.length >= 2) ...[
              const SizedBox(height: 6),
              Text(
                () {
                  final d = history[0].scores.overall - history[1].scores.overall;
                  final ds = '${d >= 0 ? '+' : ''}$d';
                  return L10n.get(context, 'pointsDelta').replaceAll('{delta}', ds);
                }(),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                summary.length > 400 ? '${summary.substring(0, 400)}…' : summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              L10n.get(context, 'generatedByLine'),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

/// Basit geri bildirim (varsayılan): "N kişi şunu istiyor" listesi + tek satır duygu.
/// Süre sonunda ve elle açıldığında gösterilen sade özet. Ağır analiz "Detaylı
/// raporu gör" ile [DetailedAudienceReportScreen]'e devreder.
class AudienceAnalysisScreen extends StatefulWidget {
  const AudienceAnalysisScreen({
    super.key,
    required this.ownerId,
    this.linkId,
    this.cacheable = false,
  });

  final String ownerId;
  final String? linkId;

  /// true: süresi dolmuş link — özet cihazda önbelleğe alınır, tekrar AI çağrısı olmaz.
  /// false: aktif link / havuz — her açılışta taze üretilir.
  final bool cacheable;

  @override
  State<AudienceAnalysisScreen> createState() => _AudienceAnalysisScreenState();
}

class _AudienceAnalysisScreenState extends State<AudienceAnalysisScreen> {
  Future<CommunityFeedbackSummary>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  void _run() {
    final lang = L10n.languageCodeForApp(context);
    setState(() {
      _future = _loadOrGenerate(lang);
    });
  }

  Future<CommunityFeedbackSummary> _loadOrGenerate(String lang) async {
    final linkId = widget.linkId;
    final canCache = widget.cacheable && linkId != null && linkId.isNotEmpty;
    if (canCache) {
      final cached = await CommunitySummaryStore.instance.load(linkId);
      if (cached != null) return cached;
    }
    final summary = await reportService.generateCommunitySummary(
      widget.ownerId,
      linkId: widget.linkId,
      languageCode: lang,
    );
    if (canCache) {
      await CommunitySummaryStore.instance.save(linkId, summary);
    }
    return summary;
  }

  void _openDetailed() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailedAudienceReportScreen(
          ownerId: widget.ownerId,
          linkId: widget.linkId,
        ),
      ),
    );
  }

  void _openComments(String linkId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AllCommentsScreen(
          linkId: linkId,
          title: L10n.get(context, 'commentsTitle'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    final linkId = widget.linkId;
    final hasLink = linkId != null && linkId.isNotEmpty;
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthWide,
      appBar:
          feedbackAppBar(context, title: L10n.get(context, 'audienceAppBarTitle')),
      body: future == null
          ? const SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.l),
              child: CommunitySummaryLoading(),
            )
          : FutureBuilder<CommunityFeedbackSummary>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.l),
                    child: CommunitySummaryLoading(),
                  );
                }
                if (snap.hasError) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.h),
                        FeedbackErrorState(
                          message: L10n.get(context, 'insightErrorTitle'),
                          retryLabel: L10n.get(context, 'retry'),
                          onRetry: _run,
                        ),
                        if (hasLink) ...[
                          const SizedBox(height: AppSpacing.m),
                          Center(
                            child: FeedbackTextButton(
                              label: L10n.get(context, 'insightSeeComments'),
                              onPressed: () => _openComments(linkId),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                final summary = snap.data;
                if (summary == null || summary.isEmpty) {
                  return FeedbackEmptyState(
                    icon: Icons.auto_awesome_rounded,
                    title: L10n.get(context, 'insightInsufficientTitle'),
                    message: L10n.get(context, 'insightInsufficientBody'),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CommunitySummaryV2View(
                        summary: summary,
                        onSeeComments:
                            hasLink ? () => _openComments(linkId) : null,
                      ),
                      if (kShowDetailedReport) ...[
                        const SizedBox(height: AppSpacing.m),
                        Center(
                          child: FeedbackTextButton(
                            label: L10n.get(context, 'detailedReportOpen'),
                            onPressed: _openDetailed,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.l),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Detaylı Creator Intelligence raporu (ağır iki-aşamalı analiz).
/// Artık varsayılan değil; basit özetin "Detaylı raporu gör" bağlantısından açılır.
class DetailedAudienceReportScreen extends StatefulWidget {
  const DetailedAudienceReportScreen({
    super.key,
    required this.ownerId,
    this.linkId,
  });

  final String ownerId;
  final String? linkId;

  @override
  State<DetailedAudienceReportScreen> createState() =>
      _DetailedAudienceReportScreenState();
}

class _DetailedAudienceReportScreenState
    extends State<DetailedAudienceReportScreen> {
  Future<AudienceAnalysisResult>? _future;
  AudienceAnalysisLoadState? _loadState;

  Future<AudienceAnalysisResult> _loadOrCreateAnalysis(String lang) async {
    final fbUid = FirebaseAuth.instance.currentUser?.uid ?? widget.ownerId;
    final recordKey = audienceRecordsOwnerKey(fbUid, widget.ownerId);

    final targetLinkId = widget.linkId;

    if (targetLinkId == null) {
      List<FeedbackLink> links = const <FeedbackLink>[];
      try {
        links = await appData
            .getLinksForOwner(widget.ownerId)
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        links = const <FeedbackLink>[];
      }
      final latestLinkId = links.isNotEmpty ? links.first.id : null;
      if (latestLinkId != null && latestLinkId.isNotEmpty) {
        try {
          final history = await appData
              .audienceScoreHistoryStream(recordKey, limit: 36)
              .first
              .timeout(const Duration(seconds: 6));
          final existing = history.where((s) => s.analyzedLinkId == latestLinkId);
          if (existing.isNotEmpty) {
            final newest = existing.first;
            final full = await appData
                .loadAudienceScoreSnapshotWithBody(recordKey, newest.id)
                .timeout(const Duration(seconds: 6));
            if (full != null) {
              return AudienceAnalysisResult.fromHistorySnapshot(full);
            }
          }
        } catch (_) {}
      }
      return reportService.generateAudienceAnalysis(
        widget.ownerId,
        analyzedLinkId: latestLinkId,
        languageCode: lang,
        onLoadUpdate: (s) {
          if (mounted) setState(() => _loadState = s);
        },
      );
    }

    // Per-link mode: check cache, then run per-link analysis
    try {
      final history = await appData
          .audienceScoreHistoryStream(recordKey, limit: 36)
          .first
          .timeout(const Duration(seconds: 6));
      final existing = history.where((s) => s.analyzedLinkId == targetLinkId);
      if (existing.isNotEmpty) {
        final newest = existing.first;
        final full = await appData
            .loadAudienceScoreSnapshotWithBody(recordKey, newest.id)
            .timeout(const Duration(seconds: 6));
        if (full != null) {
          return AudienceAnalysisResult.fromHistorySnapshot(full);
        }
      }
    } catch (_) {}

    return reportService.generateAudienceAnalysis(
      widget.ownerId,
      analyzedLinkId: targetLinkId,
      linkId: targetLinkId,
      languageCode: lang,
      onLoadUpdate: (s) {
        if (mounted) setState(() => _loadState = s);
      },
    );
  }

  void _scheduleAnalysis() {
    if (!mounted) return;
    final lang = L10n.languageCodeForApp(context);
    setState(() {
      _loadState = AudienceAnalysisLoadState(
        phase: AudienceAnalysisLoadPhase.fetchingComments,
        title: L10n.get(context, 'audienceFetchTitle'),
        subtitle: L10n.get(context, 'audienceFetchSubtitle'),
      );
      _future = _loadOrCreateAnalysis(lang);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleAnalysis();
    });
  }

  static String _audienceShareText(
    BuildContext context,
    AudienceAnalysisResult r,
    int? delta,
  ) {
    String l(String k) => L10n.get(context, k);
    final cov = r.intelligence.cover;
    final sb = StringBuffer();
    sb.writeln('${l('appTitle')} — ${l('audienceShareHeading')}');
    sb.writeln();
    sb.writeln('${l('audienceSharePool')}: ${r.feedbackCount}');
    sb.writeln(
      '${l('audienceShareMoodSplit')}: ${r.positiveCount} / ${r.neutralCount} / ${r.negativeCount}',
    );
    sb.writeln();
    sb.writeln('${l('audienceShareOverall')}: ${r.scores.overall}/100');
    sb.writeln('• ${l('audienceSharePm')}: ${r.scores.positiveMomentum}');
    sb.writeln('• ${l('audienceShareRc')}: ${r.scores.riskControl}');
    sb.writeln('• ${l('audienceShareDd')}: ${r.scores.dataDepth}');
    if (delta != null) {
      sb.writeln();
      sb.writeln('${l('audienceShareDelta')}: ${delta >= 0 ? '+' : ''}$delta');
    }
    sb.writeln();
    sb.writeln(
      '${l('audienceSharePerception')}: ${cov.communityPerception} / ${cov.trust} / ${cov.contentClarity}',
    );
    if (cov.oneLiner.trim().isNotEmpty) {
      sb.writeln('(${cov.oneLiner})');
    }
    sb.writeln();
    sb.writeln('${l('audienceShareSummary')}:');
    var summary = r.summary;
    if (summary.length > 3500) {
      summary = '${summary.substring(0, 3500)}…';
    }
    sb.writeln(summary);
    if (r.themeBullets.isNotEmpty) {
      sb.writeln();
      sb.writeln('${l('audienceShareThemes')}:');
      for (var i = 0; i < r.themeBullets.length && i < 8; i++) {
        sb.writeln('• ${r.themeBullets[i]}');
      }
    }
    if (r.actionBullets.isNotEmpty) {
      sb.writeln();
      sb.writeln('${l('audienceShareActions')}:');
      for (var i = 0; i < r.actionBullets.length && i < 8; i++) {
        sb.writeln('• ${r.actionBullets[i]}');
      }
    }
    sb.writeln();
    sb.writeln(l('audienceShareFooter'));
    return sb.toString();
  }

  Future<void> _shareAudienceAnalysis(
    BuildContext context,
    AudienceAnalysisResult result,
    int? delta,
  ) async {
    final text = _audienceShareText(context, result, delta);
    try {
      await Share.share(
        text,
        subject: L10n.get(context, 'audienceShareSubject'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L10n.get(context, 'feedbackError')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.get(context, 'audienceAppBarTitle'))),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _AudienceAnalysisLoadingPanel(state: _loadState),
          ),
        ),
      );
    }
    return FutureBuilder<AudienceAnalysisResult>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(L10n.get(context, 'audienceAppBarTitle'))),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _AudienceAnalysisLoadingPanel(state: _loadState),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(L10n.get(context, 'audienceAppBarTitle'))),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFF87171)),
                        const SizedBox(height: 16),
                        Text(
                          'Analiz sırasında hata oluştu',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          snap.error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () {
                            _scheduleAnalysis();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(L10n.get(context, 'retry')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(L10n.get(context, 'audienceAppBarTitle'))),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Analiz oluşturulamadı. Lütfen tekrar dene.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _scheduleAnalysis,
                        child: Text(L10n.get(context, 'retry')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final result = snap.data!;
        final sectionTitle = Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            );
        final fbUid =
            FirebaseAuth.instance.currentUser?.uid ?? widget.ownerId;
        final recordKey =
            audienceRecordsOwnerKey(fbUid, widget.ownerId);
        return StreamBuilder<List<AudienceScoreSnapshot>>(
          stream: appData.audienceScoreHistoryStream(recordKey),
          builder: (context, histSnap) {
            final history = histSnap.hasError
                ? const <AudienceScoreSnapshot>[]
                : (histSnap.data ?? const <AudienceScoreSnapshot>[]);
            int? delta;
            if (history.isNotEmpty) {
              final h0 = history[0];
              final likelyCurrentSnapshot = h0.feedbackCount == result.feedbackCount &&
                  h0.positiveCount == result.positiveCount &&
                  h0.neutralCount == result.neutralCount &&
                  h0.negativeCount == result.negativeCount &&
                  h0.scores.overall == result.scores.overall;
              if (likelyCurrentSnapshot && history.length >= 2) {
                delta = h0.scores.overall - history[1].scores.overall;
              } else {
                delta = result.scores.overall - h0.scores.overall;
              }
            }
            return Scaffold(
              appBar: AppBar(
                title: Text(L10n.get(context, 'audienceAppBarTitle')),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    tooltip: L10n.get(context, 'shareAudienceAnalysis'),
                    onPressed: () => _shareAudienceAnalysis(context, result, delta),
                  ),
                ],
              ),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CreatorIntelligenceReportView(
                          result: result,
                          deltaFromPrevious: delta,
                        ),
                        const SizedBox(height: 12),
                        AudienceGrowthComparisonCard(history: history),
                        const SizedBox(height: 12),
                        AudienceScoreHistorySection(
                          history: history,
                          onOpenSnapshot: (s) {
                            final idx = history.indexWhere((e) => e.id == s.id);
                            final prev = (idx >= 0 && idx + 1 < history.length)
                                ? history[idx + 1]
                                : null;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SavedAudienceReportScreen(
                                  ownerId: recordKey,
                                  snapshot: s,
                                  previousSnapshot: prev,
                                ),
                              ),
                            );
                          },
                        ),
                        if (result.relationBreakdown.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    L10n.get(context, 'relationDistributionTitle'),
                                    style: sectionTitle,
                                  ),
                                  const SizedBox(height: 8),
                                  ...result.relationBreakdown.map((r) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text('• $r'),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _shareAudienceAnalysis(context, result, delta),
                          icon: const Icon(Icons.share_rounded),
                          label: Text(L10n.get(context, 'shareAudienceAnalysis')),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ReportAnalysisScreen extends StatefulWidget {
  const ReportAnalysisScreen({super.key});

  @override
  State<ReportAnalysisScreen> createState() => _ReportAnalysisScreenState();
}

class _ReportAnalysisScreenState extends State<ReportAnalysisScreen> {
  final GlobalKey _cardKey = GlobalKey();

  Future<void> _shareAsImage() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      if (!kIsWeb) {
        try {
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) await Gal.requestAccess();
          await Gal.putImageBytes(pngBytes, name: 'feedbacktome_rapor');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.get(context, 'savedToGallery')),
            ),
          );
        } on GalException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${L10n.get(context, 'galleryError')}: ${e.type.message}')),
          );
          return;
        }
      }

      if (!mounted) return;
      _showShareOptions(context, pngBytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.get(context, 'imageError')),
        ),
      );
    }
  }

  void _showShareOptions(BuildContext context, Uint8List pngBytes) {
    final xFile = XFile.fromData(
      pngBytes,
      name: 'feedbacktome_rapor.png',
      mimeType: 'image/png',
    );
    final shareText = 'Feedback2Me gelişim analizim';

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.get(context, 'share'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (!kIsWeb)
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
                  title: Text(L10n.get(context, 'saveToGallery')),
                  subtitle: Text(L10n.get(context, 'saveToGallerySubtitle')),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final hasAccess = await Gal.hasAccess();
                      if (!hasAccess) await Gal.requestAccess();
                      await Gal.putImageBytes(pngBytes, name: 'feedbacktome_rapor');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(L10n.get(context, 'savedToGallery'))),
                        );
                      }
                    } on GalException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${L10n.get(context, 'galleryError')}: ${e.type.message}')),
                        );
                      }
                    }
                  },
                ),
              ListTile(
                leading: Icon(Icons.alternate_email, color: Theme.of(context).colorScheme.primary),
                title: Text(L10n.get(context, 'shareTwitter')),
                subtitle: Text(L10n.get(context, 'shareTwitter')),
                onTap: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles([xFile], text: shareText);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
                title: Text(L10n.get(context, 'shareInstagram')),
                subtitle: Text(L10n.get(context, 'shareInstagram')),
                onTap: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles([xFile], text: shareText);
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined, color: Theme.of(context).colorScheme.primary),
                title: Text(L10n.get(context, 'shareOther')),
                subtitle: Text(L10n.get(context, 'shareOtherSubtitle')),
                onTap: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles([xFile], text: shareText);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final oid = uid != null ? effectiveDataOwnerId(uid) : null;
    final recordKey =
        uid != null ? audienceRecordsOwnerKey(uid, oid) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.get(context, 'reportAnalysisTitle')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: uid == null
                  ? ListView(
                      children: [
                        Text(
                          L10n.get(context, 'comparePeriods'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          L10n.get(context, 'reportAnalysisLoginRequired'),
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    )
                  : BackendConfig.isRailwayBackendConfigured && oid == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                      children: [
                        Text(
                          L10n.get(context, 'comparePeriods'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          L10n.get(context, 'reportAnalysisHistoryHint'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white70, height: 1.35),
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<List<AudienceScoreSnapshot>>(
                          stream: appData
                              .audienceScoreHistoryStream(recordKey!),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  L10n.get(context, 'historyLoadFailed')
                                      .replaceAll('{e}', '${snap.error}'),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: const Color(0xFFF87171)),
                                ),
                              );
                            }
                            if (snap.connectionState == ConnectionState.waiting &&
                                !snap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final history =
                                snap.data ?? const <AudienceScoreSnapshot>[];
                            if (history.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  L10n.get(context, 'noSavedAudienceRun'),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.white60),
                                ),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AudienceGrowthComparisonCard(history: history),
                                const SizedBox(height: 12),
                                RepaintBoundary(
                                  key: _cardKey,
                                  child: _ReportSharePreviewCard(history: history),
                                ),
                                const SizedBox(height: 12),
                                AudienceScoreHistorySection(
                                  history: history,
                                  onOpenSnapshot: (s) {
                                    final idx = history.indexWhere((e) => e.id == s.id);
                                    final prev = (idx >= 0 && idx + 1 < history.length)
                                        ? history[idx + 1]
                                        : null;
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => SavedAudienceReportScreen(
                                          ownerId: recordKey,
                                          snapshot: s,
                                          previousSnapshot: prev,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AudienceAnalysisScreen(ownerId: oid!),
                              ),
                            );
                          },
                          child: Text(L10n.get(context, 'runFollowerAnalysisShort')),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _shareAsImage,
                          icon: const Icon(Icons.share_outlined),
                          label: Text(L10n.get(context, 'shareAnalysis')),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class FeedbackFormScreen extends StatefulWidget {
  const FeedbackFormScreen({super.key, this.linkCode});

  final String? linkCode;

  @override
  State<FeedbackFormScreen> createState() => _FeedbackFormScreenState();
}

class _FeedbackFormScreenState extends State<FeedbackFormScreen> {
  final _creatorSurveyKey = GlobalKey<CreatorSurveySectionState>();
  final _linkController = TextEditingController();
  final _nameController = TextEditingController();
  final _relationController = TextEditingController();
  final _feedbackController = TextEditingController();
  int _selectedMood = 0; // -1 kötü, 0 nötr, 1 iyi (reaction'dan türetilir)
  String? _selectedReaction; // FeedbackToMe 2.0 reaction anahtarı (ör. "fire")

  // V2 akış durumu — yalnızca UI. Submit'e kadar Firestore'a hiçbir ara kayıt atılmaz.
  FeedbackLink? _resolvedLink;
  bool _resolving = false;
  bool _resolveError = false; // getLinkByCode null → geçersiz/süresi dolmuş
  bool _closedError = false; // submit anında link kapandıysa (yarış)
  bool _forceManual = false; // hata sonrası manuel giriş ekranına düş
  bool _entered = false; // giriş ekranından akışa geçildi
  int _step = 0; // 0=reaction, 1=comment (yalnızca UI adımı)
  bool _submitting = false;
  bool _submitted = false;

  bool get _needsManualCode =>
      widget.linkCode == null || widget.linkCode!.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    final code = widget.linkCode;
    if (code != null && code.trim().isNotEmpty) {
      _linkController.text = code.trim();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resolve(code.trim()));
    }
  }

  /// Kodu/URL'i mevcut `_parseLinkCode` + `getLinkByCode` ile çözer.
  /// Backend davranışı değişmez; yalnızca sonucu UI durumuna bağlar.
  Future<void> _resolve(String input) async {
    final code = _parseLinkCode(input);
    if (code == null || code.isEmpty) {
      setState(() {
        _resolving = false;
        _resolveError = true;
      });
      return;
    }
    setState(() {
      _resolving = true;
      _resolveError = false;
      _forceManual = false;
    });
    try {
      final link = await appData.getLinkByCode(code);
      if (!mounted) return;
      setState(() {
        _resolving = false;
        if (link == null) {
          _resolveError = true;
        } else {
          _resolvedLink = link;
          _linkController.text = code;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = true;
      });
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    _relationController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  String? _parseLinkCode(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    String normalize(String value) {
      final cleaned = value
          .trim()
          .split(RegExp(r'[\s\?#&]'))
          .first
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      return cleaned.toLowerCase();
    }

    String? pickFromPath(String path) {
      final segments = path.split('/').where((s) => s.trim().isNotEmpty).toList();
      if (segments.isEmpty) return null;

      final fIndex = segments.lastIndexWhere((s) => s.toLowerCase() == 'f');
      if (fIndex != -1 && fIndex + 1 < segments.length) {
        return normalize(segments[fIndex + 1]);
      }
      return normalize(segments.last);
    }

    // Düz kod girişi (ör. e20393db)
    if (!raw.contains('/')) {
      final code = normalize(raw);
      return code.isEmpty ? null : code;
    }

    // Şemasız domain girdisi için (örn. feedbacktome-xxx.web.app/f/e20393db)
    final maybeUrl = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(maybeUrl);
    if (uri != null) {
      final fromPath = pickFromPath(uri.path);
      if (fromPath != null && fromPath.isNotEmpty) return fromPath;
    }

    // Uri parse edilemezse son çare olarak path bazlı ayrıştırma.
    final fallback = pickFromPath(raw);
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return; // çift-submit koruması
    if (_feedbackController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'feedbackFormTooShort'))),
      );
      setState(() => _step = 1);
      return;
    }
    final code = _parseLinkCode(_linkController.text);
    if (_resolvedLink == null && (code == null || code.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'feedbackFormInvalidLink'))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final link = _resolvedLink ?? await appData.getLinkByCode(code!);
      if (link == null) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _resolveError = true;
        });
        return;
      }
      await appData.addFeedback(
        linkId: link.id,
        responderName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        relation: _relationController.text.trim().isEmpty
            ? null
            : _relationController.text.trim(),
        mood: _selectedMood,
        reaction: _selectedReaction,
        textRaw: _feedbackController.text.trim(),
        creatorSurvey: _creatorSurveyKey.currentState?.buildPayload(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e is StateError &&
          (e.message == 'link_closed_or_expired' ||
              e.message == 'link_expired')) {
        setState(() => _closedError = true);
        return;
      }
      final msg = _feedbackSubmitErrorMessage(context, e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _feedbackSubmitErrorMessage(BuildContext context, Object e) {
    if (e is StateError) {
      switch (e.message) {
        case 'link_not_found':
          return L10n.get(context, 'feedbackFormLinkNotFound');
        case 'link_expired':
        case 'link_closed_or_expired':
          return L10n.get(context, 'feedbackFormLinkExpired');
      }
    }
    return '${L10n.get(context, 'feedbackFormSendFailed')} $e';
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccess(context);
    if (_resolveError) return _buildInvalid(context);
    if (_closedError) return _buildClosed(context);
    if (_resolving) {
      return FeedbackScaffold(
        maxWidth: AppSpacing.maxWidthForm,
        appBar: feedbackAppBar(context),
        body: FeedbackLoadingState(message: L10n.get(context, 'loading')),
      );
    }
    if (_resolvedLink == null) {
      if (_needsManualCode || _forceManual) return _buildManual(context);
      // Deeplink kodu hâlâ çözülüyor.
      return FeedbackScaffold(
        maxWidth: AppSpacing.maxWidthForm,
        appBar: feedbackAppBar(context),
        body: FeedbackLoadingState(message: L10n.get(context, 'loading')),
      );
    }
    if (!_entered) return _buildEntry(context);
    return _buildStep(context);
  }

  /// Manuel giriş (fallback) — deeplink yoksa ya da hata sonrası kurtarma.
  Widget _buildManual(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'feedbackFormTitle')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.l),
            Text(L10n.get(context, 'pfManualTitle'), style: AppType.pageTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(L10n.get(context, 'pfManualSub'), style: AppType.secondary),
            const SizedBox(height: AppSpacing.l),
            TextField(
              controller: _linkController,
              decoration: InputDecoration(
                labelText: L10n.get(context, 'feedbackFormLinkLabel'),
                hintText: L10n.get(context, 'feedbackFormLinkHint'),
                prefixIcon: const Icon(Icons.link_rounded),
              ),
              onSubmitted: _resolve,
            ),
            const SizedBox(height: AppSpacing.l),
            FeedbackPrimaryButton(
              label: L10n.get(context, 'pfManualContinue'),
              trailingArrow: true,
              onPressed: () => _resolve(_linkController.text),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// Public feedback girişi (hero + güven + başla).
  Widget _buildEntry(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.h),
            const Center(child: FeedbackBrandMark()),
            const SizedBox(height: AppSpacing.xxl),
            Center(
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: AppRadius.rLarge,
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: const Icon(Icons.reviews_rounded,
                    color: AppColors.onPrimary, size: 36),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(L10n.get(context, 'pfEntryHeroGeneric'),
                style: AppType.display, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'pfEntrySub'),
                style: AppType.secondary, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FeedbackTrustChip(
                    label: L10n.get(context, 'trustAnonymous'),
                    icon: Icons.visibility_off_rounded),
                FeedbackTrustChip(
                    label: L10n.get(context, 'trustSecure'),
                    icon: Icons.shield_rounded),
                FeedbackTrustChip(
                    label: L10n.get(context, 'trustFast'),
                    icon: Icons.bolt_rounded),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FeedbackPrimaryButton(
              label: L10n.get(context, 'pfEntryStart'),
              trailingArrow: true,
              onPressed: () => setState(() => _entered = true),
            ),
            const SizedBox(height: AppSpacing.m),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(L10n.get(context, 'pfPrivacyFooter'), style: AppType.caption),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// Adımlı akış: 1/2 Tepki, 2/2 Yorum. Firestore'a submit'e kadar yazılmaz.
  Widget _buildStep(BuildContext context) {
    final en = L10n.languageCodeForApp(context) == 'en';
    final stepLabel =
        _step == 0 ? L10n.get(context, 'pfStepReaction') : L10n.get(context, 'pfStepComment');
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(
        context,
        actions: [
          Center(
            child: Text('${_step + 1} / 2  ·  $stepLabel',
                style: AppType.secondary),
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.s),
            Row(
              children: [
                const Expanded(child: _StepDot(active: true)),
                const SizedBox(width: 6),
                Expanded(child: _StepDot(active: _step >= 1)),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            if (_step == 0)
              ..._reactionStep(context, en)
            else
              ..._commentStep(context),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  List<Widget> _reactionStep(BuildContext context, bool en) {
    return [
      Text(L10n.get(context, 'pfReactionTitle'), style: AppType.pageTitle),
      const SizedBox(height: AppSpacing.xl),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final r in kDefaultReactions)
            _ReactionChip(
              emoji: r.emoji,
              label: r.label(en),
              selected: _selectedReaction == r.key,
              onTap: () => setState(() {
                if (_selectedReaction == r.key) {
                  // Tekrar dokunma → seçimi kaldır (nötr).
                  _selectedReaction = null;
                  _selectedMood = 0;
                } else {
                  _selectedReaction = r.key;
                  _selectedMood = r.sentiment;
                }
              }),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      FeedbackPrimaryButton(
        label: L10n.get(context, 'pfNext'),
        trailingArrow: true,
        onPressed: () => setState(() => _step = 1),
      ),
    ];
  }

  List<Widget> _commentStep(BuildContext context) {
    final canSend = _feedbackController.text.trim().length >= 10;
    return [
      Text(L10n.get(context, 'pfCommentTitle'), style: AppType.pageTitle),
      const SizedBox(height: AppSpacing.xs),
      Text(L10n.get(context, 'pfCommentSub'), style: AppType.secondary),
      const SizedBox(height: AppSpacing.m),
      TextField(
        controller: _feedbackController,
        minLines: 4,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: L10n.get(context, 'pfCommentPlaceholder'),
          helperText: L10n.get(context, 'pfMinCharsHint'),
          alignLabelWithHint: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: AppSpacing.m),
      TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: L10n.get(context, 'pfNameLabel'),
          helperText: L10n.get(context, 'pfNameHelper'),
        ),
      ),
      const SizedBox(height: AppSpacing.m),
      TextField(
        controller: _relationController,
        decoration: InputDecoration(
          labelText: L10n.get(context, 'feedbackFormRelationLabel'),
        ),
      ),
      const SizedBox(height: AppSpacing.m),
      // Creator anketi henüz V2 değil (beyaz-metinli) → okunur kalması için
      // koyu-temaya sarılı. İçerik/mantık birebir korunur.
      Theme(
        data: buildFeedbackTheme(),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: const Color(0xFF141210),
            borderRadius: AppRadius.rCard,
            border: Border.all(color: AppColors.border),
          ),
          child: CreatorSurveySection(key: _creatorSurveyKey),
        ),
      ),
      const SizedBox(height: AppSpacing.m),
      Row(
        children: [
          const Icon(Icons.shield_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(L10n.get(context, 'pfPrivacyFooter'), style: AppType.caption),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.l),
      FeedbackPrimaryButton(
        label: L10n.get(context, 'send'),
        busy: _submitting,
        onPressed: canSend ? _submit : null,
      ),
      const SizedBox(height: AppSpacing.s),
      Center(
        child: FeedbackTextButton(
          label: L10n.get(context, 'back'),
          onPressed: () => setState(() => _step = 0),
        ),
      ),
    ];
  }

  Widget _buildSuccess(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context, showBack: false),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.huge),
            Center(
              child: Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.onPrimary, size: 52),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(L10n.get(context, 'pfSuccessTitle'),
                style: AppType.display, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'pfSuccessBody'),
                style: AppType.body, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(L10n.get(context, 'pfSuccessSecondary'),
                style: AppType.secondary, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxl),
            FeedbackSecondaryButton(
              label: L10n.get(context, 'pfSuccessCreateOwn'),
              icon: Icons.add_link_rounded,
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const _AuthGate()),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Center(
              child: FeedbackTextButton(
                label: L10n.get(context, 'close'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildInvalid(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context),
      body: FeedbackEmptyState(
        icon: Icons.link_off_rounded,
        title: L10n.get(context, 'pfInvalidTitle'),
        message: L10n.get(context, 'pfInvalidBody'),
        ctaLabel: L10n.get(context, 'pfManualContinue'),
        onCta: () => setState(() {
          _resolveError = false;
          _resolvedLink = null;
          _forceManual = true;
        }),
      ),
    );
  }

  Widget _buildClosed(BuildContext context) {
    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthForm,
      appBar: feedbackAppBar(context),
      body: FeedbackEmptyState(
        icon: Icons.lock_clock_rounded,
        title: L10n.get(context, 'pfClosedTitle'),
        message: L10n.get(context, 'pfInvalidBody'),
      ),
    );
  }
}

/// Adım ilerleme çubuğu noktası (public feedback akışı).
class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.border,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

/// Büyük dokunma alanlı reaction seçimi (V2).
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderRadius: AppRadius.rMedium,
        child: InkWell(
          borderRadius: AppRadius.rMedium,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: AppRadius.rMedium,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(label,
                    style: selected
                        ? AppType.bodyStrong.copyWith(color: AppColors.primary)
                        : AppType.body),
                if (selected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
