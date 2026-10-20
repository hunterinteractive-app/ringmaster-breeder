/// Showroom groups describe a set of colors, not a complete phenotype. This
/// supplies labels to the existing coat rules only when a saved color is usable.
class CoatGroup {
  final String kind;
  final String? base;
  const CoatGroup(this.kind, [this.base]);

  static const _bases = ['black', 'blue', 'chocolate', 'lilac'];
  static const _aliases = {
    'broken': 'broken',
    'broken group': 'broken',
    'broken pattern': 'broken',
    'solid': 'solid',
    'solid pattern': 'solid',
    'colored': 'colored',
    'aov': 'aov',
    'self': 'self',
    'agouti': 'agouti',
    'shaded': 'shaded',
    'tan pattern': 'tan pattern',
    'otter': 'otter',
    'otter group': 'otter',
    'silver marten group': 'silver marten',
    'fox group': 'fox',
    'sable point group': 'sable point',
    'pointed white': 'pointed white',
    'non-extension': 'non-extension',
    'ticked': 'ticked',
    'white': 'white',
    'tri-colored': 'tricolor',
    'tricolor': 'tricolor',
    'tri-color': 'tricolor',
    'tri color': 'tricolor',
  };

  static CoatGroup? fromLabel(String name) {
    final kind = _aliases[name];
    if (kind != null) return CoatGroup(kind);
    final shaded = RegExp(
      r'^shaded group - (black|blue|chocolate|lilac)$',
    ).firstMatch(name);
    return shaded == null ? null : CoatGroup('shaded', shaded[1]);
  }

  /// Null means this description still does not identify a supported color.
  String? colorLabel(String color) {
    if (color.isEmpty) return null;
    if (_bases.contains(color)) {
      return switch (kind) {
        'agouti' => 'agouti - $color',
        'otter' ||
        'silver marten' ||
        'fox' ||
        'sable point' ||
        'pointed white' => '$color $kind',
        // Black does not tell us whether a shaded rabbit is tort, sable, seal,
        // etc., or whether a tan-pattern rabbit is otter or marten.
        'shaded' ||
        'tan pattern' ||
        'non-extension' ||
        'ticked' ||
        'white' ||
        'aov' => null,
        'broken' => 'broken $color',
        'tricolor' => 'tricolor $color',
        _ => color,
      };
    }
    if (kind == 'broken') {
      if (color.startsWith('charlie ') || color.startsWith('tricolor ')) {
        return null;
      }
      return color.startsWith('broken ') ? color : 'broken $color';
    }
    if (kind == 'tricolor') {
      if (color.startsWith('tricolor ') || color.startsWith('tri-color ')) {
        return color;
      }
      if (color.contains('harlequin') && !color.startsWith('charlie ')) {
        return color.startsWith('broken ') ? color : 'broken $color';
      }
      return null;
    }
    return color;
  }

  List<String>? get families => switch (kind) {
    'self' => ['self', 'white'],
    'agouti' => ['agouti', 'chinchilla'],
    'otter' => ['otter'],
    'tan pattern' => ['otter', 'silver marten', 'sable marten'],
    'silver marten' => ['silver marten'],
    'fox' => ['fox'],
    'sable point' => ['sable point'],
    'shaded' => [
      'sable',
      'sable point',
      'seal',
      'sable marten',
      'sable agouti',
      'tortoise',
      'tort',
    ],
    'pointed white' => ['pointed white', 'himalayan'],
    'white' => ['white'],
    'non-extension' => [
      'orange',
      'tortoise',
      'tort',
      'fox',
      'frosty',
      'sable point',
    ],
    // Only an explicitly named steel color is handled. Ticked alone must not
    // be interpreted as steel, silvering, or an ordinary agouti color.
    'ticked' => ['steel'],
    'tricolor' => ['harlequin', 'japanese'],
    // The captured AOV label belongs to Jersey Wooly; its club lists pointed
    // whites and orange here. This is not a blanket alias for any color.
    'aov' => ['pointed white', 'himalayan', 'orange'],
    _ => null,
  };

  /// A reviewed example for the coverage audit, not a default for rabbit data.
  Map<String, String> get exampleDetails => {
    'color': switch (kind) {
      'agouti' => 'Chestnut',
      'otter' || 'tan pattern' => 'Black Otter',
      'silver marten' => 'Black Silver Marten',
      'fox' => 'Black Fox',
      'sable point' => 'Black Sable Point',
      'shaded' => '${base ?? 'black'} Tortoise',
      'white' => 'Ruby Eyed White',
      'non-extension' => 'Orange',
      'ticked' => 'Black Steel',
      'aov' || 'pointed white' => 'Black Pointed White',
      _ => 'Black',
    },
  };
}
