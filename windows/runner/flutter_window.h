#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "win_hotkey.h"
#include "win_screenshot.h"

class ImeCaret;

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
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Corrects Windows IME candidate position to the real caret.
  std::unique_ptr<ImeCaret> ime_caret_;

  // System-wide hotkeys. Registration fails when another program owns the chord.
  std::unique_ptr<WinHotkey> win_hotkey_;

  // Region screenshot over the frozen desktop.
  std::unique_ptr<WinScreenshot> win_screenshot_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
