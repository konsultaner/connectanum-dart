import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/ui/wamp_app_theme.dart';

void main() {
  for (final accent in WampAppAccentPreference.values) {
    for (final brightness in Brightness.values) {
      test('${accent.wireName} ${brightness.name} colors meet WCAG AA', () {
        final theme = brightness == Brightness.light
            ? WampAppTheme.light(accent)
            : WampAppTheme.dark(accent);
        final colors = theme.colorScheme;
        final textPairs = <(Color, Color, String)>[
          (colors.primary, colors.onPrimary, 'primary'),
          (
            colors.primaryContainer,
            colors.onPrimaryContainer,
            'primary container',
          ),
          (colors.secondary, colors.onSecondary, 'secondary'),
          (
            colors.secondaryContainer,
            colors.onSecondaryContainer,
            'secondary container',
          ),
          (colors.tertiary, colors.onTertiary, 'tertiary'),
          (colors.error, colors.onError, 'error'),
          (colors.errorContainer, colors.onErrorContainer, 'error container'),
          (colors.surface, colors.onSurface, 'surface'),
          (
            colors.surfaceContainerHighest,
            colors.onSurfaceVariant,
            'surface variant',
          ),
        ];

        for (final (background, foreground, label) in textPairs) {
          expect(
            _contrastRatio(background, foreground),
            greaterThanOrEqualTo(4.5),
            reason: '$label text contrast must meet WCAG AA',
          );
        }
        expect(
          _contrastRatio(colors.surfaceContainerHighest, colors.outline),
          greaterThanOrEqualTo(3),
          reason: 'input boundaries must remain distinguishable',
        );
      });
    }
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
