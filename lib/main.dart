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
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'services/auth_service.dart' show firebaseAuthUserMessage;
import 'config/backend_config.dart';
import 'services/api_session.dart' show ApiSession;
import 'services/railway_backend_sync.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/feedback_entry.dart';
import 'models/feedback_link.dart';
import 'models/audience_score.dart';
import 'models/user_profile.dart';
import 'screens/premium_screen.dart';
import 'screens/settings_screen.dart';
import 'services/report_service.dart';
import 'widgets/app_onboarding.dart';
import 'widgets/audience_score_widgets.dart';
import 'widgets/creator_intelligence_report_view.dart';
import 'widgets/creator_survey_section.dart';
import 'theme/app_theme.dart';
import 'theme/feedback_material_theme.dart';
import 'widgets/feedback_link_tile.dart';
import 'widgets/link_plan_banner.dart';
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
class _AppLaunchGate extends StatefulWidget {
  const _AppLaunchGate();

  @override
  State<_AppLaunchGate> createState() => _AppLaunchGateState();
}

class _AppLaunchGateState extends State<_AppLaunchGate> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
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
    if (_onboardingDone == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF141210),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.gold),
        ),
      );
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
    return Scaffold(
      backgroundColor: const Color(0xFF141210),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFD4AF37)),
            const SizedBox(height: 24),
            Text(
              L10n.get(context, 'loading'),
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18),
            ),
          ],
        ),
      ),
    );
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

/// AppBar başlığı: dar alanda kırpılmasın (Apple HIG: net başlık).
class _AppBarBrandTitle extends StatelessWidget {
  const _AppBarBrandTitle();

  @override
  Widget build(BuildContext context) {
    final title = L10n.get(context, 'appTitle');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: feedbackAppUsesIosTypography
          ? Alignment.center
          : Alignment.centerLeft,
      child: Text(
        title,
        maxLines: 1,
        style: Theme.of(context).appBarTheme.titleTextStyle,
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
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(L10n.get(context, 'login')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: L10n.get(context, 'back'),
        ),
      ),
      body: _DarkMysticalBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _AppBrand(),
                          const SizedBox(height: 32),
                          Text(
                            L10n.get(context, 'loginSubtitle'),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: () async {
                              try {
                                final user = await authService.signInWithGoogle();
                                if (!context.mounted) return;
                                await _afterFirebaseLoginCloseSheet(context, user);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${L10n.get(context, 'loginFailedGoogle')}: '
                                        '${firebaseAuthUserMessage(e)}',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.g_mobiledata_rounded),
                            label: Text(L10n.get(context, 'loginGoogle')),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final user = await authService.signInWithApple();
                                if (!context.mounted) return;
                                await _afterFirebaseLoginCloseSheet(context, user);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${L10n.get(context, 'loginFailedApple')}: '
                                        '${firebaseAuthUserMessage(e)}',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.apple),
                            label: Text(L10n.get(context, 'loginApple')),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.4)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(L10n.get(context, 'continueWithoutLogin')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
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
    return Scaffold(
          backgroundColor: Colors.transparent,
          body: _DarkMysticalBackground(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = _currentIndex == 0
                      ? _buildHomeContent(isLoggedIn: isLoggedIn, uid: uid)
                      : _ProfileTab(profile: profile, uid: uid);

                  // Küçük Android ekranlarda taşmayı önlemek için Home sekmesi kaydırılabilir.
                  if (_currentIndex == 0) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: content,
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: content,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          appBar: AppBar(
            title: const _AppBarBrandTitle(),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: L10n.get(context, 'settings'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (ctx) => SettingsScreen(
                        onOpenLogin: (c) {
                          Navigator.of(c).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: EdgeInsets.only(
                  right: feedbackAppUsesIosTypography ? 0 : 8,
                ),
                child: _PlanTierBadge(
                  isLoggedIn: isLoggedIn,
                  profile: profile,
                  compact: feedbackAppUsesIosTypography,
                ),
              ),
              if (isLoggedIn)
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await authService.signOut();
                  },
                  tooltip: L10n.get(context, 'logout'),
                )
              else if (feedbackAppUsesIosTypography)
                IconButton(
                  icon: const Icon(Icons.person_outline_rounded),
                  tooltip: L10n.get(context, 'login'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                )
              else
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.login, size: 20),
                  label: Text(L10n.get(context, 'login')),
                ),
            ],
          ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            label: L10n.get(context, 'home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            label: L10n.get(context, 'profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent({required bool isLoggedIn, String? uid}) {
    final theme = Theme.of(context);
    final ios = feedbackAppUsesIosTypography;
    final cardPad = ios ? 24.0 : 20.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AppBrand(),
        SizedBox(height: ios ? 28 : 24),
        const _Tagline(),
        SizedBox(height: ios ? 36 : 32),
        Card(
          child: Padding(
            padding: EdgeInsets.all(cardPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.get(context, 'createLinkCardTitle'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: ios ? 12 : 8),
                Text(
                  L10n.get(context, 'createLinkCardSubtitle'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                SizedBox(height: ios ? 14 : 8),
                Text(
                  L10n.get(context, 'createLinkTierHint'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.48),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: ios ? 22 : 16),
                _PrimaryActions(isLoggedIn: isLoggedIn, uid: uid),
              ],
            ),
          ),
        ),
        SizedBox(height: ios ? 36 : 32),
        const _FooterNote(),
      ],
    );
  }
}

class _AppBrand extends StatelessWidget {
  const _AppBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.goldDark, AppTheme.gold],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.gold.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.feedback_rounded,
            color: Color(0xFF1C1917),
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.get(context, 'appTitle'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Colors.white.withOpacity(0.98),
              ),
            ),
            Text(
              L10n.get(context, 'appSubtitle'),
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return Text(
      L10n.get(context, 'tagline'),
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            height: 1.4,
            color: Colors.white.withOpacity(0.9),
          ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({this.isLoggedIn = false, this.uid});

  final bool isLoggedIn;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isLoggedIn && uid != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _createLink(context, uid!),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                L10n.get(context, 'newLink'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final loggedIn = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                );
                if (!context.mounted) return;
                // Girişten hemen sonra link oluşturma: demo hakkı bitmiş kullanıcıda
                // createLink → premium Snackbar; kullanıcı bunu "giriş olmadı" sanıyor.
                // Link, giriş sonrası "Yeni link oluştur" ile ayrı adımda istenir.
                if (loggedIn ?? false) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          L10n.get(context, 'afterLoginUseNewLinkButton'),
                        ),
                      ),
                    );
                  });
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                L10n.get(context, 'premiumAndCreateLink'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FeedbackFormScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(
                color: Colors.white.withOpacity(0.4),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              L10n.get(context, 'writeFeedbackFromLink'),
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      '${L10n.get(context, 'footerPremium')}\n${L10n.get(context, 'footerGuests')}',
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white60,
      ),
      textAlign: TextAlign.left,
    );
  }
}

/// Üst çubuk: aktif premium veya link kredisi → Premium; ücretsiz demo → Demo; demo bitti → satın alma.
Future<void> _showDemoPlanSheet(BuildContext context, {required bool isLoggedIn}) async {
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1a1a1f),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                L10n.get(sheetCtx, 'demoSheetTitle'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                L10n.get(
                  sheetCtx,
                  isLoggedIn ? 'demoSheetBodyLoggedIn' : 'demoSheetBodyGuest',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  if (isLoggedIn) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    );
                  } else {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  L10n.get(
                    sheetCtx,
                    isLoggedIn ? 'demoSheetGoPremium' : 'demoSheetLoginFirst',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text(L10n.get(sheetCtx, 'close')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showLinkCreditSheet(BuildContext context) async {
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1a1a1f),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.get(sheetCtx, 'creditSheetTitle'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                L10n.get(sheetCtx, 'creditSheetBody'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PremiumScreen(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(L10n.get(sheetCtx, 'creditSheetOpenPremium')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text(L10n.get(sheetCtx, 'close')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PlanTierBadge extends StatelessWidget {
  const _PlanTierBadge({
    required this.isLoggedIn,
    this.profile,
    this.compact = false,
  });

  final bool isLoggedIn;
  final UserProfile? profile;

  /// iOS AppBar: metin yerine ikon + tooltip (HIG: 44pt hedef, taşma yok).
  final bool compact;

  static const Color _demoOrange = Color(0xFFEA580C);
  static const Color _demoBg = Color(0x1FEA580C);
  static const Color _slate = Color(0xFF94A3B8);
  static const Color _slateBg = Color(0x1F94A3B8);

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final premiumEligible = isLoggedIn &&
        (p?.hasActivePremium == true || (p?.paidLinkCredits ?? 0) > 0);
    final needCredit = isLoggedIn &&
        p != null &&
        p.freeDemoLinkUsed &&
        !premiumEligible;

    late final Color borderColor;
    late final Color fg;
    late final Color bg;
    late final String label;
    late final String tip;
    late final IconData icon;
    VoidCallback? onTap;

    if (premiumEligible) {
      borderColor = AppTheme.gold;
      fg = AppTheme.gold;
      bg = AppTheme.gold.withValues(alpha: 0.14);
      label = L10n.get(context, 'headerBadgePremium');
      final n = p?.paidLinkCredits ?? 0;
      tip = n > 0
          ? '${L10n.get(context, 'headerBadgePremiumTooltip')} (${L10n.get(context, 'linkCreditsCount')}: $n)'
          : L10n.get(context, 'headerBadgePremiumTooltip');
      icon = Icons.workspace_premium_rounded;
      onTap = null;
    } else if (needCredit) {
      borderColor = _slate;
      fg = _slate;
      bg = _slateBg;
      label = L10n.get(context, 'headerBadgeNeedCredit');
      tip = L10n.get(context, 'headerBadgeNeedCreditTooltip');
      icon = Icons.shopping_cart_outlined;
      onTap = () => _showLinkCreditSheet(context);
    } else {
      borderColor = _demoOrange;
      fg = _demoOrange;
      bg = _demoBg;
      label = L10n.get(context, 'headerBadgeDemo');
      tip = L10n.get(context, 'headerBadgeDemoTooltip');
      icon = Icons.timer_outlined;
      onTap = () => _showDemoPlanSheet(context, isLoggedIn: isLoggedIn);
    }

    if (compact) {
      final semanticsLabel = '$label. $tip';
      if (onTap == null) {
        return Semantics(
          label: semanticsLabel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(color: borderColor.withValues(alpha: 0.85)),
              ),
              child: Icon(icon, size: 18, color: fg),
            ),
          ),
        );
      }
      return Semantics(
        label: semanticsLabel,
        button: true,
        child: Tooltip(
          message: '$label\n$tip',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            style: IconButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              side: BorderSide(color: borderColor.withValues(alpha: 0.85)),
              shape: const CircleBorder(),
            ),
            icon: Icon(icon, size: 20),
            onPressed: onTap,
          ),
        ),
      );
    }

    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor.withValues(alpha: 0.85)),
              color: bg,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 18, color: fg),
                ],
              ],
            ),
          ),
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
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PremiumScreen(),
                ),
              );
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
    return Scaffold(
      appBar: AppBar(title: Text(L10n.get(context, 'yourLinks'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        L10n.get(context, 'linkCreated'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      LinkPlanBanner(link: link),
                      const SizedBox(height: 12),
                      SelectableText(
                        link.shareUrl,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link.shareUrl));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: Text(L10n.get(context, 'linkCopied')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Share.share(link.shareUrl);
                        },
                        icon: const Icon(Icons.share_outlined),
                        label: Text(L10n.get(context, 'shareLink')),
                      ),
                      if (link.isDemoTier) ...[
                        const SizedBox(height: 20),
                        Divider(color: Colors.white.withValues(alpha: 0.12)),
                        const SizedBox(height: 12),
                        Text(
                          L10n.get(context, 'createdLinkPremiumPitch'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white60, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const PremiumScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.workspace_premium_outlined),
                          label: Text(L10n.get(context, 'createdLinkOpenPremium')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.7),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
                                  FeedbackLinkTile(link: firstLink)
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
                                          child: FeedbackLinkTile(link: l),
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
  int _refreshTick = 0;
  int _bulkTarget = 1000;

  void _refreshPool() {
    setState(() => _refreshTick++);
  }

  Future<void> _runBulkSeed(BuildContext context, String ownerId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.get(context, 'bulkTestDataTitle')),
        content: Text(
          L10n.get(context, 'bulkTestDataBody').replaceAll('{n}', '$_bulkTarget'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.get(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.get(context, 'yes')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

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
      final written = await appData.seedBulkDemoFeedbacksForOwner(
        ownerId,
        count: _bulkTarget,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (written == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'snackCreateLinkFirst'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.get(context, 'snackCommentsAdded').replaceAll('{n}', '$written'),
            ),
          ),
        );
        _refreshPool();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.get(context, 'errorGeneric').replaceAll('{e}', '$e')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final uid = widget.uid;
    final oid = uid != null ? effectiveDataOwnerId(uid) : null;
    final theme = Theme.of(context);
    final name = profile?.displayName ?? L10n.get(context, 'profileDefaultUser');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'F';

    return ListView(
      children: [
        Text(
          L10n.get(context, 'profileSectionTitle'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(initial)),
            title: Text(name),
            subtitle: Text(
              profile?.handle ?? L10n.get(context, 'profileEditHint'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          L10n.get(context, 'feedbackPoolSectionTitle'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (kDebugMode && uid != null && oid != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: const Color(0xFF1e293b),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.get(context, 'devSeedTitle'),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.get(context, 'devSeedBody'),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          final n = await appData.seedDemoFeedbacksForOwner(oid);
                          if (!context.mounted) return;
                          if (n == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(L10n.get(context, 'snackCreateLinkFirstLong')),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  L10n.get(context, 'snackSampleCommentsAdded')
                                      .replaceAll('{n}', '$n'),
                                ),
                              ),
                            );
                            _refreshPool();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  L10n.get(context, 'snackCouldNotAdd').replaceAll('{e}', '$e'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.science_outlined),
                      label: Text(L10n.get(context, 'devSeed12')),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Toplu bot yorumları',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
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
                      onPressed: () => _runBulkSeed(context, oid!),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(
                        L10n.get(context, 'bulkBotGenerate').replaceAll('{n}', '$_bulkTarget'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (uid == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Yorum havuzunu görmek için giriş yapman gerekiyor.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          )
        else if (BackendConfig.isRailwayBackendConfigured && oid == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          _FeedbackPoolCard(
            ownerId: oid!,
            refreshTick: _refreshTick,
            onRefresh: _refreshPool,
          ),
        const SizedBox(height: 24),
        if (uid == null) ...[
          Text(
            L10n.get(context, 'previousReports'),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(L10n.get(context, 'noReportsYet')),
              subtitle: Text(L10n.get(context, 'firstReportNote')),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            L10n.get(context, 'reportAnalysisTitle'),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trending_up_outlined),
              title: Text(L10n.get(context, 'reportAnalysisTitle')),
              subtitle: Text(
                'Giriş yaptıktan sonra son analiz özetin ve gelişim kıyası burada görünür.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ),
          ),
        ] else if (BackendConfig.isRailwayBackendConfigured && oid == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          StreamBuilder<List<AudienceScoreSnapshot>>(
            stream: appData.audienceScoreHistoryStream(
              audienceRecordsOwnerKey(uid!, oid),
              limit: 12,
            ),
            builder: (context, snap) {
              final storageKey = audienceRecordsOwnerKey(uid!, oid);
              Widget errorCard(String extra) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  extra,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            snap.error.toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

              if (snap.hasError) {
                final err = snap.error.toString();
                final perm = err.contains('permission-denied');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.get(context, 'previousReports'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    errorCard(
                      perm
                          ? 'Kayıtlar yüklenemedi: Firestore güvenlik kuralları bu yolu reddediyor. '
                              'Projede güncel `firestore.rules` dosyasını '
                              '`firebase deploy --only firestore:rules` ile yayınlayın. '
                              'Kurallarda `users/{userId}` altında `audienceScoreSnapshots` için '
                              'okuma/yazma, `request.auth.uid == userId` olmalı.'
                          : 'Kayıtlar yüklenemedi.',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      L10n.get(context, 'reportAnalysisTitle'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    errorCard('Özet kartları için analiz geçmişi gerekir.'),
                  ],
                );
              }
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.get(context, 'previousReports'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      L10n.get(context, 'reportAnalysisTitle'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                );
              }
              final history = snap.data ?? const <AudienceScoreSnapshot>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10n.get(context, 'previousReports'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (history.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(L10n.get(context, 'noReportsYet')),
                        subtitle: Text(
                          '${L10n.get(context, 'firstReportNote')} '
                          '${L10n.get(context, 'firstReportExtraHint')}',
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AudienceAnalysisScreen(ownerId: oid!),
                              ),
                            );
                          },
                          child: Text(L10n.get(context, 'runAnalysis')),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    L10n.get(context, 'savedAnalysesLine')
                                        .replaceAll('{n}', '${history.length}'),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: Colors.white60),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const ReportAnalysisScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(L10n.get(context, 'growthAnalysisNav')),
                                ),
                              ],
                            ),
                          ),
                          ...history.take(6).map((s) {
                            final d = s.createdAt;
                            final dateStr =
                                '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
                                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                            final idx = history.indexWhere((e) => e.id == s.id);
                            final prev = (idx >= 0 && idx + 1 < history.length)
                                ? history[idx + 1]
                                : null;
                            return ListTile(
                              leading: const Icon(Icons.insert_chart_outlined),
                              title: Text(dateStr),
                              subtitle: Text(
                                L10n.get(context, 'scoreOverallComments')
                                    .replaceAll('{score}', '${s.scores.overall}')
                                    .replaceAll('{count}', '${s.feedbackCount}'),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.white54),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SavedAudienceReportScreen(
                                      ownerId: storageKey,
                                      snapshot: s,
                                      previousSnapshot: prev,
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                          if (history.length > 6)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const ReportAnalysisScreen(),
                                    ),
                                  );
                                },
                                child: Text(L10n.get(context, 'allHistoryCompare')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    L10n.get(context, 'reportAnalysisTitle'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (history.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              L10n.get(context, 'comparePeriods'),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              L10n.get(context, 'compareNoSavedBody'),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white60, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        AudienceAnalysisScreen(ownerId: oid!),
                                  ),
                                );
                              },
                              child: Text(L10n.get(context, 'runFollowerAnalysis')),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ReportAnalysisScreen(),
                                  ),
                                );
                              },
                              child: Text(L10n.get(context, 'goGrowthScreen')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              L10n.get(context, 'lastAnalysisTitle'),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              L10n.get(context, 'lastAnalysisBody'),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white54, height: 1.35),
                            ),
                            const SizedBox(height: 16),
                            AudienceScoreSummaryCard(
                              scores: history.first.scores,
                              deltaFromPrevious: history.length >= 2
                                  ? history.first.scores.overall -
                                      history[1].scores.overall
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            CreatorPerceptionPreviewCard(snapshot: history.first),
                            const SizedBox(height: 12),
                            AudienceGrowthComparisonCard(history: history),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final latest = history.first;
                                      final prev = history.length >= 2
                                          ? history[1]
                                          : null;
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              SavedAudienceReportScreen(
                                            ownerId: storageKey,
                                            snapshot: latest,
                                            previousSnapshot: prev,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.article_outlined),
                                    label: Text(L10n.get(context, 'fullReport')),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ReportAnalysisScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.trending_up),
                                    label: Text(L10n.get(context, 'growthShort')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        Text(
          L10n.get(context, 'yourLinks'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (uid == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                L10n.get(context, 'noLinksYet'),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          )
        else if (BackendConfig.isRailwayBackendConfigured && oid == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          StreamBuilder<List<FeedbackLink>>(
            stream: appData.linksForOwnerStream(oid!),
            builder: (context, snap) {
              final links = snap.data ?? [];
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
                              links.isEmpty
                                  ? L10n.get(context, 'noLinksYet')
                                  : '${links.length} ${L10n.get(context, 'yourLinks')}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _createLink(context, uid!),
                            icon: const Icon(Icons.add_link),
                            label: Text(L10n.get(context, 'newLink')),
                          ),
                        ],
                      ),
                      if (links.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...links.map(
                          (l) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FeedbackLinkTile(link: l),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
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
    return FutureBuilder<(List<FeedbackEntry>, int)>(
      key: ValueKey('pool_${ownerId}_$refreshTick'),
      future: () async {
        final entries =
            await appData.getFeedbackPoolForOwner(ownerId, limit: 80);
        final total = await appData.countAllFeedbacksForOwner(ownerId);
        return (entries, total);
      }(),
      builder: (context, snap) {
        final errorText = snap.error?.toString();
        final entries = snap.data?.$1 ?? const <FeedbackEntry>[];
        final totalAll = snap.data?.$2 ?? 0;
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
                        totalAll > 0
                            ? '${L10n.get(context, 'poolTotal').replaceAll('{n}', '$totalAll')}'
                                '${entries.length < totalAll ? L10n.get(context, 'poolPreview').replaceAll('{m}', '${entries.length}') : ''}'
                            : L10n.get(context, 'poolGrowing')
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
                if (snap.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      L10n.get(context, 'poolReadError').replaceAll('{e}', '$errorText'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.orangeAccent),
                    ),
                  ),
                if (entries.isEmpty)
                  Text(
                    L10n.get(context, 'poolEmptyHint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  )
                else ...[
                  ...entries.take(6).map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '• ${e.textRaw}\n'
                        '  ${e.relation?.trim().isNotEmpty == true ? e.relation! : L10n.get(context, 'relationUnknown')} · ${_moodLabel(context, e.mood)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ),
                  if (entries.length > 6)
                    Text(
                      L10n.get(context, 'poolMore')
                          .replaceAll('{n}', '${entries.length - 6}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AudienceAnalysisScreen(ownerId: ownerId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(L10n.get(context, 'aiAudienceAnalysisRun')),
                ),
              ],
            ),
          ),
        );
      },
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

class AudienceAnalysisScreen extends StatefulWidget {
  const AudienceAnalysisScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<AudienceAnalysisScreen> createState() => _AudienceAnalysisScreenState();
}

class _AudienceAnalysisScreenState extends State<AudienceAnalysisScreen> {
  Future<AudienceAnalysisResult>? _future;
  AudienceAnalysisLoadState? _loadState;

  Future<AudienceAnalysisResult> _loadOrCreateAnalysis(String lang) async {
    final fbUid = FirebaseAuth.instance.currentUser?.uid ?? widget.ownerId;
    final recordKey = audienceRecordsOwnerKey(fbUid, widget.ownerId);
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
      } catch (_) {
        // History fetch timed out/failed; continue with fresh analysis.
      }
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
  int _selectedMood = 0; // -1 kötü, 0 nötr, 1 iyi

  @override
  void initState() {
    super.initState();
    if (widget.linkCode != null && widget.linkCode!.isNotEmpty) {
      _linkController.text = widget.linkCode!;
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
    if (_feedbackController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.get(context, 'feedbackFormTooShort')),
        ),
      );
      return;
    }
    final code = _parseLinkCode(_linkController.text);
    if (code == null || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.get(context, 'feedbackFormInvalidLink')),
        ),
      );
      return;
    }
    try {
      final link = await appData.getLinkByCode(code);
      if (link == null || !context.mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.get(context, 'feedbackFormLinkNotFound'))),
          );
        }
        return;
      }
      await appData.addFeedback(
        linkId: link.id,
        responderName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        relation: _relationController.text.trim().isEmpty ? null : _relationController.text.trim(),
        mood: _selectedMood,
        textRaw: _feedbackController.text.trim(),
        creatorSurvey: _creatorSurveyKey.currentState?.buildPayload(),
      );
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(L10n.get(context, 'feedbackFormSuccessTitle')),
            content: Text(L10n.get(context, 'feedbackFormSuccessBody')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext)
                    ..pop()
                    ..pop();
                },
                child: Text(L10n.get(context, 'close')),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      final msg = _feedbackSubmitErrorMessage(context, e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
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

  Widget _feedbackHowStep(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAppMarketingUrl() async {
    final uri = Uri.parse(FeedbackLink.appMarketingBaseUrl);
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'feedbackFormCouldNotOpenLink'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${L10n.get(context, 'feedbackFormCouldNotOpenLink')} $e'),
          ),
        );
      }
    }
  }

  void _openPremiumScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.get(context, 'feedbackFormTitle')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                children: [
                  Text(
                    L10n.get(context, 'feedbackFormIntroLead'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    L10n.get(context, 'feedbackFormHowItWorksTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _feedbackHowStep(
                    theme,
                    Icons.add_link_rounded,
                    L10n.get(context, 'feedbackFormHowStep1'),
                  ),
                  _feedbackHowStep(
                    theme,
                    Icons.chat_bubble_outline_rounded,
                    L10n.get(context, 'feedbackFormHowStep2'),
                  ),
                  _feedbackHowStep(
                    theme,
                    Icons.auto_fix_high_rounded,
                    L10n.get(context, 'feedbackFormHowStep3'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _linkController,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'feedbackFormLinkLabel'),
                      hintText: L10n.get(context, 'feedbackFormLinkHint'),
                      prefixIcon: const Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_moon_outlined,
                              size: 22,
                              color: theme.colorScheme.primary.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                L10n.get(context, 'feedbackFormPrivacyTitle'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          L10n.get(context, 'feedbackFormPrivacyBody'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white70, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'feedbackFormNameLabel'),
                      hintText: L10n.get(context, 'feedbackFormNameHint'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _relationController,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'feedbackFormRelationLabel'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10n.get(context, 'feedbackFormMoodQuestion'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(L10n.get(context, 'moodNegative')),
                        selected: _selectedMood == -1,
                        onSelected: (_) {
                          setState(() {
                            _selectedMood = -1;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(L10n.get(context, 'moodNeutral')),
                        selected: _selectedMood == 0,
                        onSelected: (_) {
                          setState(() {
                            _selectedMood = 0;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(L10n.get(context, 'moodPositive')),
                        selected: _selectedMood == 1,
                        onSelected: (_) {
                          setState(() {
                            _selectedMood = 1;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _feedbackController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: L10n.get(context, 'feedbackFormThoughtsLabel'),
                      alignLabelWithHint: true,
                      hintText: L10n.get(context, 'feedbackFormThoughtsHint'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  CreatorSurveySection(key: _creatorSurveyKey),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      L10n.get(context, 'send'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Divider(color: Colors.white.withValues(alpha: 0.12)),
                  const SizedBox(height: 16),
                  Text(
                    L10n.get(context, 'feedbackFormFooterDiscover'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: _openAppMarketingUrl,
                        child: Text(L10n.get(context, 'feedbackFormOpenApp')),
                      ),
                      Text(
                        '·',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                      ),
                      TextButton(
                        onPressed: _openPremiumScreen,
                        child: Text(L10n.get(context, 'feedbackFormGoPremium')),
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
