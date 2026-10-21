#include "win_hotkey.h"

#include <flutter/encodable_value.h>

#include <string>

namespace {

constexpr int kAlreadyRegistered = 1409;

}  // namespace

WinHotkey::WinHotkey(flutter::BinaryMessenger* messenger, HWND host)
    : host_(host) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "caoim/hotkey", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleCall(call, std::move(result)); });
}

WinHotkey::~WinHotkey() {
  UnregisterAll();
  channel_->SetMethodCallHandler(nullptr);
}

bool WinHotkey::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  if (message != WM_HOTKEY || hwnd != host_ || channel_ == nullptr) {
    return false;
  }
  channel_->InvokeMethod(
      "onHotKey",
      std::make_unique<flutter::EncodableValue>(static_cast<int>(wparam)));
  return true;
}

void WinHotkey::UnregisterAll() {
  for (const int id : ids_) {
    UnregisterHotKey(host_, id);
  }
  ids_.clear();
}

bool WinHotkey::ReadInt(const flutter::EncodableMap& map, const char* key,
                        int* out) const {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return false;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    *out = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    *out = static_cast<int>(*value);
    return true;
  }
  return false;
}

void WinHotkey::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "toggleWindow") {
    WINDOWPLACEMENT placement{};
    placement.length = sizeof(placement);
    GetWindowPlacement(host_, &placement);
    const bool hidden = !IsWindowVisible(host_) || IsIconic(host_) ||
                        placement.showCmd == SW_SHOWMINIMIZED;
    if (hidden) {
      ShowWindow(host_, SW_RESTORE);
      SetForegroundWindow(host_);
    } else {
      ShowWindow(host_, SW_MINIMIZE);
    }
    result->Success();
    return;
  }

  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  int id = 0;
  if (args == nullptr || !ReadInt(*args, "id", &id)) {
    result->Error("bad_args", "Hotkey id is missing.");
    return;
  }

  if (call.method_name() == "unregister") {
    UnregisterHotKey(host_, id);
    ids_.erase(id);
    result->Success();
    return;
  }

  if (call.method_name() != "register") {
    result->NotImplemented();
    return;
  }

  int modifiers = 0;
  int vk = 0;
  if (!ReadInt(*args, "modifiers", &modifiers) || !ReadInt(*args, "vk", &vk) ||
      vk == 0) {
    result->Error("bad_args", "Hotkey chord is invalid.");
    return;
  }

  UnregisterHotKey(host_, id);
  ids_.erase(id);
  if (!RegisterHotKey(host_, id, static_cast<UINT>(modifiers),
                      static_cast<UINT>(vk))) {
    const bool taken = GetLastError() == kAlreadyRegistered;
    result->Success(flutter::EncodableValue(taken ? "conflict" : "failed"));
    return;
  }
  ids_.insert(id);
  result->Success(flutter::EncodableValue("ok"));
}
