#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "ime_caret.h"
#include "win_hotkey.h"
#include "win_screenshot.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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
  ime_caret_ = std::make_unique<ImeCaret>(
      flutter_controller_->engine()->messenger(), GetHandle(),
      flutter_controller_->view()->GetNativeWindow());
  win_hotkey_ = std::make_unique<WinHotkey>(
      flutter_controller_->engine()->messenger(), GetHandle());
  win_screenshot_ = std::make_unique<WinScreenshot>(
      flutter_controller_->engine()->messenger());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  win_screenshot_ = nullptr;
  win_hotkey_ = nullptr;
  ime_caret_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (win_hotkey_ && win_hotkey_->HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }

  if (ime_caret_ && ime_caret_->HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    // Flutter often parks the IME window at caret offset 0. Re-apply the true
    // caret after that update, deferred so we never re-enter IMM APIs.
    if (ime_caret_ && ime_caret_->active() &&
        (message == WM_IME_STARTCOMPOSITION || message == WM_IME_COMPOSITION ||
         message == WM_IME_NOTIFY || message == WM_IME_SETCONTEXT)) {
      ime_caret_->ScheduleReapply();
    }
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
