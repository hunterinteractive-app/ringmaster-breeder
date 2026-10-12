import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
external JSDateTimeFormat _dateTimeFormat();
extension type JSDateTimeFormat(JSObject _) implements JSObject {
  external JSTimezoneOptions resolvedOptions();
}
extension type JSTimezoneOptions(JSObject _) implements JSObject {
  external String get timeZone;
}
String deviceTimezone() => _dateTimeFormat().resolvedOptions().timeZone;
