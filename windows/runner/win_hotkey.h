#ifndef RUNNER_WIN_HOTKEY_H_
#define RUNNER_WIN_HOTKEY_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <unordered_set>

#include <windows.h>

namespace flutter {
class BinaryMessenger;
class EncodableValue;
}  // namespace flutter

// Registers system-wide hotkeys on the Flutter window thread.
// RegisterHotKey fails when another program already owns the same chord.
class WinHotkey {
 public:
  WinHotkey(flutter::BinaryMessenger* messenger, HWND host);
  ~WinHotkey();

  WinHotkey(const WinHotkey&) = delete;
  WinHotkey& operator=(const WinHotkey&) = delete;

  bool HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UnregisterAll();
  bool ReadInt(const flutter::EncodableMap& map, const char* key, int* out) const;

  HWND host_ = nullptr;
  std::unordered_set<int> ids_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_WIN_HOTKEY_H_
