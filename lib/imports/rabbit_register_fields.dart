/// Reads Evans' documented and observed field spellings without rewriting raw
/// snapshots. Conflicting aliases require correction instead of picking a value.
class RabbitRegisterFields {
  final Map raw;
  final String label;

  RabbitRegisterFields(this.raw, {this.label = 'Rabbit Register record'});

  static String key(String name) =>
      switch (name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')) {
        'earnumber' => 'earnum',
        'winnings' => 'wins',
        'forsalepprice' => 'forsaleprice',
        final value => value,
      };

  String? operator [](String name) => read(name);

  String? read(String name, {List<String> aliases = const []}) {
    final keys = {key(name), ...aliases.map(key)};
    final values = {
      for (final entry in raw.entries)
        if (keys.contains(key(entry.key.toString())) &&
            entry.value != null &&
            entry.value.toString().trim().isNotEmpty)
          entry.value.toString().trim(),
    };
    if (values.length > 1) {
      throw FormatException('Conflicting values for $name in $label.');
    }
    return values.firstOrNull;
  }
}
