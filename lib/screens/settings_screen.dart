import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart'
    show authService, localeNotifier, appData, effectiveDataOwnerId;
import '../design_system/design_system.dart';
import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../widgets/app_onboarding.dart';
import 'premium_screen.dart';

/// Ayarlar — V2 aydınlık grouped-list. Davranışlar (dil, hesap, çıkış,
/// onboarding, legal linkleri) BİREBİR korunur; yalnızca sunum yenilenir.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onOpenLogin,
    this.developerToolsBuilder,
  });

  final void Function(BuildContext context) onOpenLogin;

  /// Yalnız debug build'de (kDebugMode) çağıran tarafından geçilir → "Geliştirici"
  /// bölümü görünür. Release'de null → bölüm widget tree'sinde YOK.
  final WidgetBuilder? developerToolsBuilder;

  static final Uri _privacyPolicyUri =
      Uri.parse('https://feedbacktome-79655.web.app/privacy');
  static final Uri _termsUri =
      Uri.parse('https://feedbacktome-79655.web.app/terms');
  static final Uri _supportEmailUri =
      Uri.parse('mailto:support@feedbacktome.app');

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!context.mounted) return;
    if (!ok) {
      if (uri.scheme == 'https') {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _InAppLegalPage(
              title: uri.path.contains('privacy')
                  ? L10n.get(context, 'settingsPrivacyPolicy')
                  : L10n.get(context, 'settingsTerms'),
              url: uri.toString(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.get(context, 'settingsLinkOpenFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final uid = user?.uid;
    final oid = uid != null ? (effectiveDataOwnerId(uid) ?? uid) : null;

    return FeedbackScaffold(
      maxWidth: AppSpacing.maxWidthContent,
      appBar: feedbackAppBar(context, title: L10n.get(context, 'settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
        children: [
          Text(L10n.get(context, 'settingsSubtitle'), style: AppType.secondary),
          const SizedBox(height: AppSpacing.l),

          // HESAP
          FeedbackSettingsSection(
            title: L10n.get(context, 'settingsAccount'),
            children: [
              if (user == null)
                FeedbackSettingsTile(
                  icon: Icons.login_rounded,
                  title: L10n.get(context, 'login'),
                  subtitle: L10n.get(context, 'settingsAccountGuest'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary),
                  onTap: () => onOpenLogin(context),
                )
              else
                _AccountTile(
                  name: user.displayName,
                  email: user.email,
                  photoUrl: user.photoURL,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          // PLAN / KREDİ (yalnız giriş yapıldıysa; gerçek değer)
          if (oid != null) ...[
            _PlanSection(
              ownerId: oid,
              onOpenPremium: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
              ),
            ),
          ],

          // DİL
          ValueListenableBuilder<Locale?>(
            valueListenable: localeNotifier,
            builder: (context, override, _) {
              return FeedbackSettingsSection(
                title: L10n.get(context, 'settingsLanguage'),
                children: [
                  _LanguageOptionTile(
                    label: L10n.get(context, 'turkish'),
                    locale: const Locale('tr'),
                    current: override,
                  ),
                  _LanguageOptionTile(
                    label: L10n.get(context, 'english'),
                    locale: const Locale('en'),
                    current: override,
                  ),
                  _LanguageOptionTile(
                    label: L10n.get(context, 'systemLanguage'),
                    locale: null,
                    current: override,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.l),

          // UYGULAMA (onboarding tekrar)
          FeedbackSettingsSection(
            title: L10n.get(context, 'settingsIntro'),
            children: [
              FeedbackSettingsTile(
                icon: Icons.auto_awesome_rounded,
                tone: SettingsIconTone.violet,
                title: L10n.get(context, 'settingsReplayIntro'),
                subtitle: L10n.get(context, 'settingsReplayIntroHint'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) =>
                        AppOnboarding(onFinished: () => Navigator.of(ctx).pop()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          // DESTEK / HAKKINDA
          FeedbackSettingsSection(
            title: L10n.get(context, 'settingsLegal'),
            children: [
              FeedbackSettingsTile(
                icon: Icons.privacy_tip_outlined,
                tone: SettingsIconTone.neutral,
                title: L10n.get(context, 'settingsPrivacyPolicy'),
                subtitle: L10n.get(context, 'settingsPrivacyPolicyHint'),
                trailing: const Icon(Icons.open_in_new_rounded,
                    size: 18, color: AppColors.textSecondary),
                onTap: () => _openExternal(context, _privacyPolicyUri),
              ),
              FeedbackSettingsTile(
                icon: Icons.gavel_outlined,
                tone: SettingsIconTone.neutral,
                title: L10n.get(context, 'settingsTerms'),
                subtitle: L10n.get(context, 'settingsTermsHint'),
                trailing: const Icon(Icons.open_in_new_rounded,
                    size: 18, color: AppColors.textSecondary),
                onTap: () => _openExternal(context, _termsUri),
              ),
              FeedbackSettingsTile(
                icon: Icons.support_agent_rounded,
                tone: SettingsIconTone.neutral,
                title: L10n.get(context, 'settingsSupport'),
                subtitle: L10n.get(context, 'settingsSupportHint'),
                trailing: const Icon(Icons.mail_outline_rounded,
                    size: 18, color: AppColors.textSecondary),
                onTap: () => _openExternal(context, _supportEmailUri),
              ),
              FeedbackSettingsTile(
                icon: Icons.info_outline_rounded,
                tone: SettingsIconTone.neutral,
                title: L10n.get(context, 'appTitle'),
                subtitle: L10n.get(context, 'appVersion'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          // ÇIKIŞ (yalnız giriş yapıldıysa)
          if (user != null) ...[
            FeedbackSettingsSection(
              title: L10n.get(context, 'settingsAccount'),
              children: [
                FeedbackSettingsTile(
                  icon: Icons.logout_rounded,
                  danger: true,
                  title: L10n.get(context, 'logout'),
                  onTap: () async {
                    await authService.signOut();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
          ],

          // GELİŞTİRİCI (yalnız debug — caller kDebugMode ile geçer)
          if (developerToolsBuilder != null) ...[
            FeedbackSettingsSection(
              title: L10n.get(context, 'settingsV2Developer'),
              children: [
                FeedbackSettingsTile(
                  icon: Icons.build_rounded,
                  tone: SettingsIconTone.neutral,
                  title: L10n.get(context, 'profileV2DeveloperTools'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: developerToolsBuilder!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
          ],

          Text(L10n.get(context, 'settingsPrivacyNote'),
              style: AppType.caption),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({this.name, this.email, this.photoUrl});

  final String? name;
  final String? email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final displayName = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()
        : L10n.get(context, 'premiumUser');
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          FeedbackAvatar(name: displayName, imageUrl: photoUrl, size: 46),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: AppType.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (email != null && email!.isNotEmpty)
                  Text(email!,
                      style: AppType.secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plan/kredi bölümü — gerçek [UserProfile] değerinden. Değer yoksa gizlenir.
class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.ownerId, required this.onOpenPremium});

  final String ownerId;
  final VoidCallback onOpenPremium;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: appData.userProfileStream(ownerId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const SizedBox.shrink();
        final premium = p.hasActivePremium;
        final credits = p.paidLinkCredits;
        return Column(
          children: [
            FeedbackSettingsSection(
              title: L10n.get(context, 'settingsV2Plan'),
              children: [
                FeedbackSettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  tone: SettingsIconTone.primary,
                  title: L10n.get(context, 'settingsV2Plan'),
                  trailing: Text(
                    premium
                        ? L10n.get(context, 'tierPremium')
                        : L10n.get(context, 'tierFree'),
                    style: AppType.bodyStrong.copyWith(color: AppColors.primary),
                  ),
                  onTap: onOpenPremium,
                ),
                FeedbackSettingsTile(
                  icon: Icons.confirmation_number_outlined,
                  tone: SettingsIconTone.success,
                  title: L10n.get(context, 'settingsV2LinkCredits'),
                  trailing: Text('$credits',
                      style: AppType.bodyStrong
                          .copyWith(color: AppColors.textPrimary)),
                  onTap: onOpenPremium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
          ],
        );
      },
    );
  }
}

/// Dil seçeneği satırı — mevcut L10n.setLocale sistemini kullanır.
class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.label,
    required this.locale,
    required this.current,
  });

  final String label;
  final Locale? locale;
  final Locale? current;

  @override
  Widget build(BuildContext context) {
    final selected = locale == null
        ? current == null
        : current?.languageCode == locale!.languageCode;
    return FeedbackSettingsTile(
      icon: locale == null
          ? Icons.smartphone_rounded
          : Icons.translate_rounded,
      tone: SettingsIconTone.primary,
      title: label,
      selected: selected,
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : null,
      onTap: () => L10n.setLocale(locale),
    );
  }
}

/// URL tarayıcıda açılamazsa in-app fallback (nadir; koyu kalır).
class _InAppLegalPage extends StatelessWidget {
  const _InAppLegalPage({required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF141210),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE8C547),
                          )),
                      const SizedBox(height: 12),
                      Text(url,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white54)),
                      const SizedBox(height: 16),
                      Text(
                        L10n.get(context, 'settingsLegalFallbackBody'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white70, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(url);
                          try {
                            await launchUrl(uri,
                                mode: LaunchMode.platformDefault);
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.open_in_browser_rounded),
                        label:
                            Text(L10n.get(context, 'settingsLegalOpenBrowser')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.get(context, 'settingsSupport'),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('support@feedbacktome.app',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFFE8C547))),
                      const SizedBox(height: 4),
                      Text(L10n.get(context, 'settingsSupportHint'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white54)),
                    ],
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
