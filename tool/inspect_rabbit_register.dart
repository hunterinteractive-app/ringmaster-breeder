// Local inspection only. No network or database calls. Optional JSON output
// contains personal source data: write it outside the repository.
import 'dart:convert';
import 'dart:io';
import 'package:ringmaster_breeder/imports/rabbit_register_xml.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/inspect_rabbit_register.dart input.xml [output.json]',
    );
    exitCode = 64;
    return;
  }
  final export = RabbitRegisterExport.parse(File(args.first).readAsBytesSync());
  stdout.writeln(
    jsonEncode({
      'counts': export.counts,
      'recovered': export.recovered,
      'unknown_sex': export.animals.where((a) => a['sex'] == null).length,
      'active': export.animals.where((a) => a['status'] == 'active').length,
      'warnings': export.warnings.length,
      'parent_links_needing_review': export.parentProblems({}).length,
    }),
  );
  if (args.length == 2) {
    File(args[1]).writeAsStringSync(
      jsonEncode({
        ...export.payload(acknowledged: true),
        'review_parent_links': export.parentProblems({}),
      }),
    );
  }
}
