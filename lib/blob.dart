import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A context, drawn as a soft cloud of colour with its name across the middle.
///
/// No edge, no card, no icon. A hard-edged circle reads as a button and invites
/// you to compare it with the ones beside it; a blurred one reads as an area,
/// which is what a context is — and it lets sizes differ by a few pixels
/// without looking like a mistake.
class Blob extends StatelessWidget {
  const Blob({
    super.key,
    required this.label,
    required this.colour,
    required this.size,
    this.shared = false,
    this.dragging = false,
  });

  final String label;
  final Color colour;

  /// Diameter of the colour, which use has decided.
  final double size;

  /// Whether this context also lives somewhere else, so it can be marked as
  /// shared rather than mistaken for a copy.
  final bool shared;

  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Blurred rather than a soft gradient: a gradient still has an
          // outermost ring you can pick out, and these have to sit on top of
          // each other without either looking cut.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: size * 0.17,
              sigmaY: size * 0.17,
              tileMode: TileMode.decal,
            ),
            child: Container(
              width: size * 0.78,
              height: size * 0.78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colour.withValues(alpha: dragging ? 0.95 : 0.8),
              ),
            ),
          ),
          if (shared)
            Positioned(
              width: size * 0.86,
              height: size * 0.86,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colour.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: size * 1.15,
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: meshText(
                size: 11,
                weight: 500,
                letterSpacing: 1.4,
                height: 1.25,
                color: MeshColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
