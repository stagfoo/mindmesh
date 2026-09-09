/// How much a context is used, and how big that makes it.
///
/// Counted per *edge* — parent and child together — because a context's weight
/// is only meaningful inside the context you are looking at it from. The gym
/// you open every morning is big in "morning" and small in "health", and both
/// are true.
///
/// Decay is lazy: nothing ticks in the background. An entry's real count is
/// worked out from how long it has been since it was touched, whenever anyone
/// asks. A launcher that needed a running timer to keep its circles honest
/// would be spending battery to do arithmetic.
///
/// Pure Dart, with the clock passed in, so every case — a week of decay, a
/// count already at the floor, a burst of opens — is testable exactly.
library;

import 'dart:math' as math;

class Usage {
  const Usage({required this.clicks, required this.lastUpdated});

  final int clicks;
  final DateTime lastUpdated;


  Map<String, dynamic> toJson() =>
      {'clicks': clicks, 'lastUpdated': lastUpdated.millisecondsSinceEpoch};

  static Usage? fromJson(Object? json) {
    if (json is! Map) return null;
    final clicks = json['clicks'];
    final at = json['lastUpdated'];
    if (clicks is! num || at is! num) return null;
    return Usage(
      clicks: math.max(0, clicks.round()),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }
}

class UsageStyle {
  const UsageStyle({
    this.decayEvery = const Duration(minutes: 30),
    this.baseSize = 92,
    this.scaleFactor = 30,
    this.maxSize = 240,
  });

  /// One click falls off per this much elapsed time.
  final Duration decayEvery;

  /// The size a context with no use at all is drawn at. Never zero: an unused
  /// context still has to be findable and pressable.
  final double baseSize;

  /// How much each doubling of use is worth, in pixels of diameter.
  final double scaleFactor;

  /// A ceiling, so one runaway context cannot swallow the whole view.
  final double maxSize;

  static const standard = UsageStyle();
}

/// Diameter for a count.
///
/// Logarithmic: the first few opens should be plainly visible, and the
/// hundredth should not be twenty times the size of the tenth. `clicks + 1`
/// keeps log(0) out of it and makes the very first open show.
double circleSize(int clicks, {UsageStyle style = UsageStyle.standard}) {
  final safe = math.max(0, clicks);
  final size = style.baseSize + math.log(safe + 1) * style.scaleFactor;
  return math.min(size, style.maxSize);
}

/// The counters, keyed by [edgeKey].
class UsageBook {
  const UsageBook(this.entries);

  const UsageBook.empty() : entries = const {};

  final Map<String, Usage> entries;

  /// How many clicks an edge really has *now*, with elapsed decay applied but
  /// nothing written back. This is what the view asks.
  int clicksAt(String key, DateTime now, {UsageStyle style = UsageStyle.standard}) {
    final usage = entries[key];
    if (usage == null) return 0;
    return math.max(0, usage.clicks - _steps(usage.lastUpdated, now, style));
  }

  double sizeAt(String key, DateTime now,
          {UsageStyle style = UsageStyle.standard}) =>
      circleSize(clicksAt(key, now, style: style), style: style);

  /// Records an open: catch up on decay, then add one.
  ///
  /// This is the only place the book is written, which is what makes the lazy
  /// decay safe — there is no window in which a count is stale on disk and
  /// nobody has looked.
  UsageBook opened(String key, DateTime now,
      {UsageStyle style = UsageStyle.standard}) {
    final clicks = clicksAt(key, now, style: style) + 1;
    return UsageBook({
      ...entries,
      key: Usage(clicks: clicks, lastUpdated: now),
    });
  }

  /// Forgets everything about edges that no longer exist.
  UsageBook keepingOnly(Set<String> liveKeys) => UsageBook({
        for (final entry in entries.entries)
          if (liveKeys.contains(entry.key)) entry.key: entry.value,
      });

  int _steps(DateTime since, DateTime now, UsageStyle style) {
    final elapsed = now.difference(since);
    if (elapsed.isNegative) return 0;
    final every = style.decayEvery.inMilliseconds;
    if (every <= 0) return 0;
    return elapsed.inMilliseconds ~/ every;
  }

  Map<String, dynamic> toJson() =>
      {for (final entry in entries.entries) entry.key: entry.value.toJson()};

  static UsageBook fromJson(Object? json) {
    if (json is! Map) return const UsageBook.empty();
    final entries = <String, Usage>{};
    for (final entry in json.entries) {
      final key = entry.key;
      final usage = Usage.fromJson(entry.value);
      if (key is String && usage != null) entries[key] = usage;
    }
    return UsageBook(entries);
  }
}
