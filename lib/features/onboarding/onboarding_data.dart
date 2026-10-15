import 'package:flutter/material.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

/// Static content for one onboarding page (and the matching guide step).
///
/// Titles/descriptions resolve through [AppLocalizations] so the same
/// data drives the onboarding PageView and the in-app guide screen.
class OnboardingStep {
  const OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) description;
}

/// The five first-run steps, in order.
final onboardingSteps = <OnboardingStep>[
  OnboardingStep(
    icon: Icons.movie_creation_outlined,
    title: (l10n) => l10n.onbWelcomeTitle,
    description: (l10n) => l10n.onbWelcomeDesc,
  ),
  OnboardingStep(
    icon: Icons.add_circle_outline,
    title: (l10n) => l10n.onbProjectTitle,
    description: (l10n) => l10n.onbProjectDesc,
  ),
  OnboardingStep(
    icon: Icons.content_cut_outlined,
    title: (l10n) => l10n.onbTimelineTitle,
    description: (l10n) => l10n.onbTimelineDesc,
  ),
  OnboardingStep(
    icon: Icons.palette_outlined,
    title: (l10n) => l10n.onbColorTitle,
    description: (l10n) => l10n.onbColorDesc,
  ),
  OnboardingStep(
    icon: Icons.file_download_outlined,
    title: (l10n) => l10n.onbExportTitle,
    description: (l10n) => l10n.onbExportDesc,
  ),
];
