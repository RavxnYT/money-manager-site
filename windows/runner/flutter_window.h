#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  enum class FrameMode {
    kBorderless,  // Covers full monitor (incl. taskbar area), no chrome
    kMaximized,   // Overlapped window, maximized to work area, has title bar
    kNormal,      // Centered 1280x720-style window
  };

  void ApplyBorderlessFullscreen();
  void ApplyMaximizedWindowed();
  void ApplyNormalWindowed();
  void OnF11();
  void OnEscape();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  FrameMode frame_mode_ = FrameMode::kBorderless;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
