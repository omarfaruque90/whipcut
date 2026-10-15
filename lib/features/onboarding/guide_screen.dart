import 'package:flutter/material.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

import 'onboarding_data.dart';

/// In-app user guide, reachable from Settings → "How to use".
///
/// Reuses the onboarding steps as an expandable list, plus a Tips
/// section. Available any time — unlike the first-run onboarding.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.howToUse)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (int i = 0; i < onboardingSteps.length; i++)
            _StepCard(index: i, step: onboardingSteps[i]),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              l10n.tipsTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Card(
            child: Column(
              children: [
                _TipTile(
                  icon: Icons.save_outlined,
                  text: l10n.tipAutosave,
                ),
                const Divider(height: 1, indent: 56),
                _TipTile(
                  icon: Icons.block_outlined,
                  text: l10n.tipNoWatermark,
                ),
                const Divider(height: 1, indent: 56),
                _TipTile(
                  icon: Icons.wifi_off_outlined,
                  text: l10n.tipOffline,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// One guide step as an expandable card.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.step});

  final int index;
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(step.icon, color: WhipcutTheme.amber),
        title: Text(
          '${index + 1}. ${step.title(l10n)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              step.description(l10n),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WhipcutTheme.textSecondary,
                    height: 1.6,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the Tips section.
class _TipTile extends StatelessWidget {
  const _TipTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: WhipcutTheme.amber),
      title: Text(text),
    );
  }
}
