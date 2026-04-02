import 'package:xml/xml.dart';

import '../notification_progress.dart';

/// Converts a [WindowsProgressBar] to XML
extension ProgressBarToXml on WindowsProgressBar {
  /// Serializes this progress bar to Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-progress
  void buildXml(XmlBuilder builder) {
    final attributes = <String, String>{
      'status': status,
      'value': '{$id-progressValue}',
    };
    final t = title;
    if (t != null) attributes['title'] = t;
    if (label != null) {
      attributes['valueStringOverride'] = '{$id-progressString}';
    }
    builder.element('progress', attributes: attributes);
  }

  /// The data bindings for this progress bar.
  ///
  /// To support dynamic updates, [buildXml] will inject placeholder strings
  /// called data bindings instead of actual values. This can then be updated
  /// dynamically later by calling
  /// [FlutterLocalNotificationsWindows.updateProgressBar].
  Map<String, String> get data {
    final m = <String, String>{
      '$id-progressValue': value?.toString() ?? 'indeterminate',
    };
    final l = label;
    if (l != null) m['$id-progressString'] = l;
    return m;
  }
}
