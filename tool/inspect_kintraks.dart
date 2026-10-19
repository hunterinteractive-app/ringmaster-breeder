import 'dart:convert';
import 'dart:io';
import 'package:ringmaster_breeder/imports/kintraks_csv.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError(
      'Provide a Kintraks CSV path and optional JSON output path.',
    );
  }
  final e = KintraksExport.parse(File(args.first).readAsBytesSync());
  final payload = e.payload(acknowledged: true);
  if (args.length > 1) File(args[1]).writeAsStringSync(jsonEncode(payload));
  stdout.writeln(
    jsonEncode({
      'animals': e.animals.length,
      'parent_links': e.animals.fold<int>(
        0,
        (n, a) =>
            n + (a['sire_id'] == null ? 0 : 1) + (a['dam_id'] == null ? 0 : 1),
      ),
      'weights': e.animals.where((a) => a['profile_weight'] != null).length,
      'warnings': e.warnings,
      'parent_problems': e.parentProblems({}),
    }),
  );
}
