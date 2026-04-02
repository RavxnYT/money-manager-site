import 'package:xml/xml.dart';

import '../notification_input.dart';

/// Converts a [WindowsTextInput] to XML
extension TextInputToXml on WindowsTextInput {
  /// Serializes this input to Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-input
  void buildXml(XmlBuilder builder) {
    final attrs = <String, String>{
      'id': id,
      'type': type.name,
    };
    final t = title;
    if (t != null) attrs['title'] = t;
    final ph = placeHolderContent;
    if (ph != null) attrs['placeHolderContent'] = ph;
    builder.element('input', attributes: attrs);
  }
}

/// Converts a [WindowsSelectionInput] to XML
extension SelectionInputToXml on WindowsSelectionInput {
  /// Serializes this input to Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-input
  void buildXml(XmlBuilder builder) {
    final attrs = <String, String>{
      'id': id,
      'type': type.name,
    };
    final t = title;
    if (t != null) attrs['title'] = t;
    final d = defaultItem;
    if (d != null) attrs['defaultInput'] = d;
    builder.element(
      'input',
      attributes: attrs,
      nest: () {
        for (final WindowsSelection item in items) {
          item.buildXml(builder);
        }
      },
    );
  }
}

/// Converts a [WindowsSelection] to XML
extension SelectionToXml on WindowsSelection {
  /// Serializes this selection to Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-selection
  void buildXml(XmlBuilder builder) => builder.element(
    'selection',
    attributes: <String, String>{'id': id, 'content': content},
  );
}
