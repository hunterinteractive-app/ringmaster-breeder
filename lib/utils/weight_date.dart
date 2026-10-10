import 'package:intl/intl.dart';

String weightDate(String timestamp) =>
    DateFormat('MM-dd-yy HH:mm').format(DateTime.parse(timestamp).toLocal());
