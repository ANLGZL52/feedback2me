import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kOnboardingPrefsKey = 'feedbacktome_onboarding_v1_completed';

Future<bool> isOnboardingCompleted() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(kOnboardingPrefsKey) ?? false;
}

Future<void> setOnboardingCompleted() async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(kOnboardingPrefsKey, true);
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? badge;
}

/// İlk açılış: vaatler ve ürün özeti — dokunarak veya kaydırarak ilerler.
class AppOnboarding extends StatefulWidget {
  const AppOnboarding({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<AppOnboarding> createState() => _AppOnboardingState();
}

class _AppOnboardingState extends State<AppOnboarding> {
  static const _gold = Color(0xFFE8C547);
  static const _goldDim = Color(0xFFD4AF37);

  final PageController _controller = PageController();
  int _index = 0;

  static const List<_Slide> _slides = [
    _Slide(
      icon: Icons.auto_awesome_rounded,
      title: 'Gerçek geri bildirim,\nnet içgörü',
      body:
          'FeedbackToMe ile takipçilerinden anonim, dürüst yorumlar topla. '
          'Kısayol linkin tek; paylaşımı sen kontrol edersin.',
      badge: 'Başlangıç',
    ),
    _Slide(
      icon: Icons.link_rounded,
      title: 'Bir link,\nsınırsız dinlenme',
      body:
          'Kendi geri bildirim linkini oluştur, bio veya hikâyede paylaş. '
          'Yorumlar tek havuzda birikir; kimlik gizli kalır.',
      badge: 'Toplama',
    ),
    _Slide(
      icon: Icons.psychology_alt_rounded,
      title: 'AI ile takipçi\nanalizi',
      body:
          'Yorum havuzunu yapay zekâ ile işle: duygu dağılımı, temalar ve '
          'uygulanabilir öneriler. İstersen kayıtlı raporlarla gelişimini izle.',
      badge: 'Derinlemesine',
    ),
    _Slide(
      icon: Icons.trending_up_rounded,
      title: 'Gelişimini\ngör',
      body:
          'Zaman içinde puan ve özetlerle ilerlemen görünür. '
          'Rapor gelişim ekranıyla kendini ve kitleni daha iyi tanı.',
      badge: 'Büyüme',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      HapticFeedback.lightImpact();
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      HapticFeedback.mediumImpact();
      widget.onFinished();
    }
  }

  void _prev() {
    if (_index > 0) {
      HapticFeedback.selectionClick();
      _controller.previousPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a0a2e),
              Color(0xFF0d0d14),
              Color(0xFF0a0a0f),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _gold.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          'FeedbackToMe',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onFinished,
                          child: Text(
                            'Atla',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) {
                        final s = _slides[i];
                        return _OnboardingPage(
                          slide: s,
                          gold: _gold,
                          goldDim: _goldDim,
                          onTapAdvance: _next,
                          onTapBack: _prev,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + bottomInset),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_slides.length, (i) {
                            final active = i == _index;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 28 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: active
                                    ? _gold
                                    : Colors.white.withValues(alpha: 0.2),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: const Color(0xFF1a1a1a),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _index < _slides.length - 1
                                  ? 'Devam et'
                                  : 'Başlayalım',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'İlerlemek için düğmeye bas veya sayfayı kaydır',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.slide,
    required this.gold,
    required this.goldDim,
    required this.onTapAdvance,
    required this.onTapBack,
  });

  final _Slide slide;
  final Color gold;
  final Color goldDim;
  final VoidCallback onTapAdvance;
  final VoidCallback onTapBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final w = constraints.maxWidth;
            final x = d.localPosition.dx;
            if (x > w * 0.62) {
              onTapAdvance();
            } else if (x < w * 0.38) {
              onTapBack();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (slide.badge != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: gold.withValues(alpha: 0.45)),
                        color: gold.withValues(alpha: 0.08),
                      ),
                      child: Text(
                        slide.badge!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: goldDim,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        gold.withValues(alpha: 0.2),
                        gold.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Icon(
                    slide.icon,
                    size: 72,
                    color: gold,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  slide.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  slide.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chevron_left_rounded,
                        color: Colors.white.withValues(alpha: 0.25), size: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Sol / sağ dokunuş · kaydır',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white30,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.25), size: 20),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
