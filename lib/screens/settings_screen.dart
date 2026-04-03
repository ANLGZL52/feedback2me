import 'package:flutter/material.dart';

import '../app_state.dart' show authService, localeNotifier;
import '../l10n/app_localizations.dart';
import '../widgets/app_onboarding.dart';

/// Ana uygulama temasına uyumlu ayarlar (dil, hesap, tanıtım, hakkında).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onOpenLogin,
  });

  /// [LoginScreen] `main.dart` içinde; döngüsel import önlemek için callback.
  final void Function(BuildContext context) onOpenLogin;

  static const _gold = Color(0xFFE8C547);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF141210),
      appBar: AppBar(
        title: Text(L10n.get(context, 'settings')),
      ),
      body: Container(
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
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                L10n.get(context, 'settingsSubtitle'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle(text: L10n.get(context, 'settingsLanguage')),
              const SizedBox(height: 8),
              ValueListenableBuilder<Locale?>(
                valueListenable: localeNotifier,
                builder: (context, value, child) {
                  return Card(
                    child: Column(
                      children: [
                        _LanguageTile(
                          label: L10n.get(context, 'turkish'),
                          locale: const Locale('tr'),
                        ),
                        const Divider(height: 1),
                        _LanguageTile(
                          label: L10n.get(context, 'english'),
                          locale: const Locale('en'),
                        ),
                        const Divider(height: 1),
                        _LanguageTile(
                          label: L10n.get(context, 'systemLanguage'),
                          locale: null,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _SectionTitle(text: L10n.get(context, 'settingsAccount')),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: user == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              L10n.get(context, 'settingsAccountGuest'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => onOpenLogin(context),
                              icon: const Icon(Icons.login_rounded),
                              label: Text(L10n.get(context, 'login')),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: _gold.withValues(alpha: 0.2),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: _gold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.displayName?.trim().isNotEmpty == true
                                            ? user.displayName!
                                            : L10n.get(context, 'premiumUser'),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (user.email != null &&
                                          user.email!.isNotEmpty)
                                        Text(
                                          user.email!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: Colors.white54,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await authService.signOut();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              icon: const Icon(Icons.logout_rounded),
                              label: Text(L10n.get(context, 'logout')),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(text: L10n.get(context, 'settingsIntro')),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_rounded, color: _gold),
                  title: Text(L10n.get(context, 'settingsReplayIntro')),
                  subtitle: Text(
                    L10n.get(context, 'settingsReplayIntroHint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (ctx) => AppOnboarding(
                          onFinished: () => Navigator.of(ctx).pop(),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(text: L10n.get(context, 'settingsAbout')),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            L10n.get(context, 'appTitle'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _gold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            L10n.get(context, 'appVersion'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.get(context, 'settingsAboutBody'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.white.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    L10n.get(context, 'settingsPrivacyNote'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.45),
                      height: 1.45,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFFE8C547),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.locale,
  });

  final String label;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final override = localeNotifier.value;
    final selected = locale == null
        ? override == null
        : override?.languageCode == locale!.languageCode;

    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () async {
        await L10n.setLocale(locale);
      },
    );
  }
}
