#ifndef RUNNER_IME_CARET_H_
#define RUNNER_IME_CARET_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include <windows.h>

namespace flutter {
class BinaryMessenger;
class EncodableValue;
}  // namespace flutter

// Syncs the Windows IME candidate window to the real text caret.
//
// Flutter Windows falls back to caret offset 0 when the composing rect is
// missing, so the candidate window sticks to the left of the field. Dart
// reports the true caret; we re-apply after Flutter's own IME handling.
class ImeCaret {
 public:
  ImeCaret(flutter::BinaryMessenger* messenger, HWND host, HWND view);
  ~ImeCaret();

  ImeCaret(const ImeCaret&) = delete;
  ImeCaret& operator=(const ImeCaret&) = delete;

  bool active() const { return active_; }

  // Call after Flutter has processed an IME message on the host window.
  void ScheduleReapply();

  // Handle deferred re-apply posted to the host window.
  bool HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Apply();
  HWND ImmWindow() const;

  HWND host_ = nullptr;
  HWND view_ = nullptr;
  bool active_ = false;
  bool applying_ = false;
  bool reapply_posted_ = false;
  RECT caret_{};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_IME_CARET_H_
