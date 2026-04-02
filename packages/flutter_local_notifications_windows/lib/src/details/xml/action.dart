import 'package:xml/xml.dart';
import '../notification_action.dart';

/// Converts a [WindowsAction] to XML
extension ActionToXml on WindowsAction {
  /// Serializes this notification action as Windows-compatible XML.
  ///
  /// See: https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-action#syntax
  void buildXml(XmlBuilder builder) {
    final attrs = <String, String>{
      'content': content,
      'arguments': arguments,
      'activationType': activationType.name,
      'afterActivationBehavior': activationBehavior.name,
    };
    if (placement != null) attrs['placement'] = placement!.name;
    if (imageUri != null) attrs['imageUri'] = imageUri!.toString();
    final iid = inputId;
    if (iid != null) attrs['hint-inputId'] = iid;
    if (buttonStyle != null) attrs['hint-buttonStyle'] = buttonStyle!.name;
    final tip = tooltip;
    if (tip != null) attrs['hint-toolTip'] = tip;
    builder.element('action', attributes: attrs);
  }
}
