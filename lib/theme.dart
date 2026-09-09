/// The look: near-black ground, saturated nodes, black text on colour.
///
/// The colour is what makes a node recognisable at a glance from across a
/// zoomed-out map, so everything around it stays out of the way.
library;

import 'package:flutter/material.dart';

import 'card_style.dart';
import 'icon_catalogue.dart';

class MeshColors {
  static const ground = Color(0xFF08080A);
  static const strip = Color(0xFF101014);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceEdge = Color(0xFF2A2A32);
  static const text = Color(0xFFF4F4F7);
  static const textDim = Color(0xFF83838F);

  /// Text and glyphs on a palette card. Every palette colour is chosen so black
  /// reads on it, which is what keeps the stack looking like one thing. Custom
  /// colours are not chosen — see [onNodeFor], which picks per colour.
  static const onCard = Color(0xFF0A0A0C);

  /// The light counterpart, for a custom colour too dark to take black.
  static const onCardLight = Color(0xFFF7F7FA);
}

class MeshMetrics {
  /// The action row along the bottom. Slim: it is two icons, and every pixel
  /// it takes is one the deck does not get.
  static const actionsHeight = 40.0;
  /// The full right band is the scrub area — a thin track would be a hairline
  /// target on a screen this small. The visible parts sit inside it.
  /// How big a node is drawn at scale 1. The layout works in these units.
  static const nodeSize = 96.0;
  static const gutter = 12.0;
  static const nodeRadius = 24.0;
}

Color colorOf(String key) => Color(colorForKey(key).value);

/// What to draw on top of [background].
///
/// The twelve palette colours were all picked to take black, so this only ever
/// changes its mind for a custom one. Letting the picker offer any colour
/// without this would let someone choose a navy card and lose the card's own
/// name into it.
///
/// The threshold is the WCAG contrast crossover: black wins on a background
/// whose relative luminance is above about 0.179, white below it.
Color onNodeFor(Color background) =>
    background.computeLuminance() > 0.179
        ? MeshColors.onCard
        : MeshColors.onCardLight;

/// [onNodeFor] for a stored key.
Color onNodeForKey(String key) => onNodeFor(colorOf(key));

/// Glyph for a stored icon key.
///
/// The model holds names, not Flutter types, so this is the one place the two
/// vocabularies meet — now a lookup into the generated catalogue rather than a
/// switch someone had to keep extending by hand.
IconData iconOf(String key) =>
    materialIcons[normaliseIconKey(key)] ?? Icons.folder_rounded;

/// Text in Lexend at a given weight.
///
/// Lexend ships as one variable font with a wght axis. Measured on this engine,
/// [TextStyle.fontWeight] alone does drive that axis — identical advance widths
/// to setting [FontVariation] explicitly — so this is not working around a bug.
/// Both are set anyway: the axis is then stated outright rather than depending
/// on that mapping continuing to hold, and fontWeight keeps fallback fonts and
/// any synthetic bolding honest. font_test.dart measures real widths, so if the
/// mapping ever changes it fails rather than silently flattening every weight.
TextStyle meshText({
  required double size,
  int weight = 400,
  Color color = MeshColors.text,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Lexend',
    fontSize: size,
    color: color,
    fontWeight: FontWeight.values.firstWhere(
      (candidate) => candidate.value == weight,
      orElse: () => FontWeight.normal,
    ),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: letterSpacing,
    height: height,
  );
}

ThemeData buildMeshTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: MeshColors.ground,
    colorScheme: const ColorScheme.dark(
      surface: MeshColors.ground,
      primary: Color(0xFFFF4F00),
      onPrimary: MeshColors.onCard,
    ),
    fontFamily: 'Lexend',
    textTheme: const TextTheme().apply(
      fontFamily: 'Lexend',
      bodyColor: MeshColors.text,
      displayColor: MeshColors.text,
    ),
  );
}
