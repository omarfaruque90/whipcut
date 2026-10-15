import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whipcut/core/locale_provider.dart';
import 'package:whipcut/core/theme.dart';
import 'package:whipcut/models/color_adjust.dart';

import 'color_filters.dart';

/// One-tap filter gallery shown at the top of the Color panel.
///
/// Tapping a card writes the preset's [ColorAdjust] into the selected clip
/// (LUT is preserved). Custom presets saved via "Save as preset" appear
/// after the built-ins and can be removed with a long-press.
/// Localized inline (EN/বাং) via [localeProvider] — no arb changes needed.
class FilterGallery extends ConsumerWidget {
  const FilterGallery({
    super.key,
    required this.currentAdjust,
    required this.onApply,
  });

  /// The selected clip's current color adjustments.
  final ColorAdjust currentAdjust;

  /// Writes a new look into the selected clip. Receives the preset's
  /// [ColorAdjust] (LUT preserved by the caller).
  final ValueChanged<ColorAdjust> onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isBn = ref.watch(localeProvider).languageCode == 'bn';
    final customAsync = ref.watch(_customPresetsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isBn ? 'ফিল্টার' : 'Filters',
                  style: theme.textTheme.titleMedium,
                ),
                OutlinedButton.icon(
                  onPressed: () => _showSaveDialog(context, ref, isBn),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(isBn ? 'প্রিসেট সেভ' : 'Save as preset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
              children: [
                _PresetCard(
                  name: isBn ? 'কোনোটা না' : 'None',
                  colors: const [Color(0xFF232329), Color(0xFF101012)],
                  selected: _isNeutral(currentAdjust),
                  icon: Icons.block,
                  onTap: () => onApply(
                    ColorAdjust(lutPath: currentAdjust.lutPath),
                  ),
                ),
                for (final preset in kBuiltinPresets)
                  _PresetCard(
                    name: preset.nameFor(isBn ? 'bn' : 'en'),
                    colors: preset.thumbColors,
                    selected: preset.matches(currentAdjust),
                    onTap: () => onApply(
                      preset.adjust.copyWith(lutPath: currentAdjust.lutPath),
                    ),
                  ),
                ...customAsync.when(
                  loading: () => const <Widget>[],
                  error: (_, _) => const <Widget>[],
                  data: (customs) => [
                    for (final c in customs)
                      _PresetCard(
                        name: c.name,
                        colors: const [
                          Color(0xFF2E2E35),
                          Color(0xFF8A5A00),
                        ],
                        selected: _matchesAdjust(c.adjust, currentAdjust),
                        onTap: () => onApply(
                          c.adjust.copyWith(lutPath: currentAdjust.lutPath),
                        ),
                        onLongPress: () =>
                            _confirmDelete(context, ref, isBn, c),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isBn
                  ? 'ফিল্টার এক ক্লিকে লাগে; আসল রেন্ডার এক্সপোর্টে হয়।'
                  : 'One tap applies the look; the true render happens at export.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static bool _isNeutral(ColorAdjust a) =>
      a.exposure == 0 &&
      a.contrast == 1 &&
      a.saturation == 1 &&
      a.temperature == 0 &&
      a.lift == 0 &&
      a.tealOrange == 0;

  static bool _matchesAdjust(ColorAdjust a, ColorAdjust b) =>
      (a.exposure - b.exposure).abs() < 1e-6 &&
      (a.contrast - b.contrast).abs() < 1e-6 &&
      (a.saturation - b.saturation).abs() < 1e-6 &&
      (a.temperature - b.temperature).abs() < 1e-6 &&
      (a.lift - b.lift).abs() < 1e-6 &&
      (a.tealOrange - b.tealOrange).abs() < 1e-6;

  Future<void> _showSaveDialog(
      BuildContext context, WidgetRef ref, bool isBn) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBn ? 'প্রিসেট সেভ করুন' : 'Save preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(
            hintText: isBn ? 'প্রিসেটের নাম' : 'Preset name',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isBn ? 'বাতিল' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(isBn ? 'সেভ' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await saveCustomPreset(name, currentAdjust);
    ref.invalidate(_customPresetsProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    bool isBn,
    CustomFilterPreset preset,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBn ? 'প্রিসেট মুছুন' : 'Delete preset'),
        content: Text(isBn
            ? '«${preset.name}» মুছে ফেলবেন?'
            : 'Delete "${preset.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isBn ? 'বাতিল' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: WhipcutTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isBn ? 'মুছুন' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await deleteCustomPreset(preset.id);
      ref.invalidate(_customPresetsProvider);
    }
  }
}

final _customPresetsProvider =
    FutureProvider.autoDispose<List<CustomFilterPreset>>(
        (ref) => loadCustomPresets());

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.name,
    required this.colors,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onLongPress,
  });

  final String name;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: selected
                      ? WhipcutTheme.amber
                      : WhipcutTheme.surfaceOutline,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon,
                        color: WhipcutTheme.textSecondary, size: 28)
                    : selected
                        ? const Icon(Icons.check_circle,
                            color: WhipcutTheme.amber, size: 28)
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? WhipcutTheme.amber
                  : WhipcutTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
