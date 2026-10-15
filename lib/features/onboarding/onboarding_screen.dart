import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/l10n/generated/app_localizations.dart';

import 'onboarding_data.dart';
import 'onboarding_providers.dart';

/// First-run onboarding: a 5-page intro shown once on the first launch.
///
/// Shown by the launch gate in main.dart while [onboardingDoneProvider]
/// is false. The done flag is written only via [_finish] (Get started or
/// Skip), so quitting mid-way shows onboarding again next launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() =>
      ref.read(onboardingControllerProvider.notifier).markDone();

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLast = _page == onboardingSteps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip row — hidden on the last page where the CTA takes over.
            SizedBox(
              height: 48,
              child: isLast
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(l10n.onbSkip),
                      ),
                    ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: onboardingSteps.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) =>
                    _OnboardingPage(step: onboardingSteps[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                onboardingSteps.length,
                (index) => _Dot(active: index == _page),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLast ? _finish : _nextPage,
                  child: Text(isLast ? l10n.onbGetStarted : l10n.next),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// One onboarding page: large amber icon, title, short description.
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: WhipcutTheme.amber.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: WhipcutTheme.amber.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Icon(step.icon, size: 56, color: WhipcutTheme.amber),
          ),
          const SizedBox(height: 32),
          Text(
            step.title(l10n),
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 24),
          ),
          const SizedBox(height: 12),
          Text(
            step.description(l10n),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium
                ?.copyWith(color: WhipcutTheme.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// Page-indicator dot.
class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? WhipcutTheme.amber : WhipcutTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
