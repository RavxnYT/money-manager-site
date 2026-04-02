import 'package:xml/xml.dart';

import '../notification_parts.dart';

/// Converts a [WindowsNotificationText] to XML
extension TextToXml on WindowsNotificationText {
  /// Serializes this text to Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-text
  void buildXml(XmlBuilder builder) {
    final attrs = <String, String>{
      'hint-callScenarioCenterAlign': centerIfCall.toString(),
      'hint-align': 'center',
    };
    final lc = languageCode;
    if (lc != null) attrs['lang'] = lc;
    if (placement != null) attrs['placement'] = placement!.name;
    if (isCaption) attrs['hint-style'] = 'captionsubtle';
    builder.element('text', attributes: attrs, nest: text);
  }
}
