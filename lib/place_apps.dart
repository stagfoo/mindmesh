import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'models.dart';
import 'node.dart';
import 'theme.dart';

/// The apps a place holds, shown when you arrive at it.
///
/// A panel rather than more nodes on the canvas: the map is a picture of your
/// situations, and apps are what you do once you are in one. Drawn over the
/// canvas at a fixed size so it stays readable however far out the map is
/// zoomed — the apps are the thing you came here to press.
class PlaceApps extends StatelessWidget {
  const PlaceApps({
    super.key,
    required this.place,
    required this.apps,
    required this.onLaunch,
    required this.onHold,
    required this.onAdd,
    required this.onClose,
  });

  final MapNode place;

  /// Installed apps by id; a missing one is shown greyed rather than hidden.
  final Map<String, LaunchableApp> apps;

  final ValueChanged<String> onLaunch;
  final ValueChanged<String> onHold;
  final VoidCallback onAdd;
  final VoidCallback onClose;

  static const _iconSize = 52.0;
  static const _columns = 4;

  @override
  Widget build(BuildContext context) {
    final colour = colorOf(place.colorKey);

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: MeshColors.strip,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colour.withValues(alpha: 0.55), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(iconOf(place.iconKey), size: 16, color: colour),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  place.label,
                  overflow: TextOverflow.ellipsis,
                  style: meshText(size: 15, weight: 600),
                ),
              ),
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Add apps',
                onTap: onAdd,
              ),
              const SizedBox(width: 4),
              _RoundButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (place.apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nothing here yet',
                textAlign: TextAlign.center,
                style: meshText(size: 12, color: MeshColors.textDim),
              ),
            )
          else
            // Scrolls rather than growing: a place with thirty apps in it must
            // not push its own edges off the screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: GridView.count(
                crossAxisCount: _columns,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                mainAxisSpacing: 14,
                crossAxisSpacing: 6,
                childAspectRatio: 0.78,
                children: [
                  for (final appId in place.apps)
                    _AppTile(
                      appId: appId,
                      app: apps[appId],
                      onTap: () => onLaunch(appId),
                      onHold: () => onHold(appId),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.appId,
    required this.app,
    required this.onTap,
    required this.onHold,
  });

  final String appId;
  final LaunchableApp? app;
  final VoidCallback onTap;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final installed = app;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onHold,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: PlaceApps._iconSize,
            height: PlaceApps._iconSize,
            child: installed == null
                // Kept rather than hidden: you put it here, and a silent gap
                // is more confusing than something plainly greyed out.
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: MeshColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.help_outline_rounded,
                        color: MeshColors.textDim),
                  )
                : AppIconImage(app: installed, size: PlaceApps._iconSize),
          ),
          const SizedBox(height: 6),
          Text(
            installed?.label ?? appId.split('/').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: meshText(size: 10, color: MeshColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: MeshColors.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: MeshColors.text),
        ),
      ),
    );
  }
}
