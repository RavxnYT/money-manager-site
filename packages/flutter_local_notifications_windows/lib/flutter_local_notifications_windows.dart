// Dart-only Windows implementation (no ATL / MSVC C++ build).
// Upstream uses native code that requires Visual Studio ATL (atlbase.h).
// This app only uses notifications on Android/iOS; Windows is a no-op.
export 'src/details.dart';
export 'src/msix/stub.dart';
export 'src/plugin/stub.dart';
