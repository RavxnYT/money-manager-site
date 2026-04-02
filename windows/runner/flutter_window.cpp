#include "flutter_window.h"

#include <optional>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::ApplyBorderlessFullscreen() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return;
  }

  const RECT& bounds = monitor_info.rcMonitor;

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
             WS_SYSMENU | WS_BORDER | WS_DLGFRAME);
  style |= WS_POPUP;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
                WS_EX_STATICEDGE);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  SetWindowPos(hwnd, HWND_TOP, bounds.left, bounds.top, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  frame_mode_ = FrameMode::kBorderless;
}

void FlutterWindow::ApplyMaximizedWindowed() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
                WS_EX_STATICEDGE);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~WS_POPUP;
  style |= WS_OVERLAPPEDWINDOW;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  ShowWindow(hwnd, SW_SHOWMAXIMIZED);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  frame_mode_ = FrameMode::kMaximized;
}

void FlutterWindow::ApplyNormalWindowed() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
                WS_EX_STATICEDGE);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~WS_POPUP;
  style |= WS_OVERLAPPEDWINDOW;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  constexpr int kClientWidth = 1280;
  constexpr int kClientHeight = 720;
  RECT client_rect = {0, 0, kClientWidth, kClientHeight};
  AdjustWindowRectEx(&client_rect, static_cast<DWORD>(WS_OVERLAPPEDWINDOW),
                     FALSE, 0);
  const int win_w = client_rect.right - client_rect.left;
  const int win_h = client_rect.bottom - client_rect.top;

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const RECT& work = monitor_info.rcWork;
  const int x = work.left + (work.right - work.left - win_w) / 2;
  const int y = work.top + (work.bottom - work.top - win_h) / 2;

  ShowWindow(hwnd, SW_SHOWNORMAL);
  SetWindowPos(hwnd, HWND_TOP, x, y, win_w, win_h,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  frame_mode_ = FrameMode::kNormal;
}

void FlutterWindow::OnF11() {
  // Always return to a normal move/size window (Chrome with title bar).
  ApplyNormalWindowed();
}

void FlutterWindow::OnEscape() {
  // Borderless -> maximized (fullscreen but with frame). Maximized -> borderless.
  // Normal -> maximized.
  switch (frame_mode_) {
    case FrameMode::kBorderless:
      ApplyMaximizedWindowed();
      break;
    case FrameMode::kMaximized:
      ApplyBorderlessFullscreen();
      break;
    case FrameMode::kNormal:
      ApplyMaximizedWindowed();
      break;
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    ApplyBorderlessFullscreen();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_KEYDOWN && wparam == VK_F11) {
    OnF11();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == WM_KEYDOWN && wparam == VK_ESCAPE) {
    OnEscape();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
