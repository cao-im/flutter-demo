#include "ime_caret.h"

#include <flutter/encodable_value.h>

#include <imm.h>

#include <string>

namespace {

constexpr UINT kReapplyMessage = WM_APP + 41;

bool ReadLong(const flutter::EncodableMap& map, const char* key, LONG* out) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return false;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    *out = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    *out = static_cast<LONG>(*value);
    return true;
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    *out = static_cast<LONG>(*value);
    return true;
  }
  return false;
}

}  // namespace

ImeCaret::ImeCaret(flutter::BinaryMessenger* messenger, HWND host, HWND view)
    : host_(host), view_(view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "caoim/ime", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleCall(call, std::move(result)); });
}

ImeCaret::~ImeCaret() {
  channel_->SetMethodCallHandler(nullptr);
}

void ImeCaret::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "clearCaret") {
    active_ = false;
    result->Success();
    return;
  }
  if (call.method_name() != "updateCaret") {
    result->NotImplemented();
    return;
  }

  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  LONG left = 0;
  LONG top = 0;
  LONG right = 0;
  LONG bottom = 0;
  if (args == nullptr || !ReadLong(*args, "left", &left) ||
      !ReadLong(*args, "top", &top) || !ReadLong(*args, "right", &right) ||
      !ReadLong(*args, "bottom", &bottom)) {
    result->Error("bad_args", "IME caret rect is invalid.");
    return;
  }

  caret_.left = left;
  caret_.top = top;
  caret_.right = right > left ? right : left + 1;
  caret_.bottom = bottom > top ? bottom : top + 1;
  active_ = true;
  Apply();
  result->Success();
}

void ImeCaret::ScheduleReapply() {
  if (!active_ || host_ == nullptr || reapply_posted_) {
    return;
  }
  reapply_posted_ = true;
  ::PostMessage(host_, kReapplyMessage, 0, 0);
}

bool ImeCaret::HandleMessage(HWND hwnd,
                             UINT message,
                             WPARAM wparam,
                             LPARAM lparam) {
  if (message != kReapplyMessage) {
    return false;
  }
  reapply_posted_ = false;
  Apply();
  return true;
}

HWND ImeCaret::ImmWindow() const {
  const HWND focus = ::GetFocus();
  if (view_ != nullptr && focus == view_) {
    return view_;
  }
  if (host_ != nullptr && focus == host_) {
    return host_;
  }
  if (view_ != nullptr) {
    return view_;
  }
  return host_;
}

void ImeCaret::Apply() {
  if (!active_ || applying_) {
    return;
  }

  const HWND hwnd = ImmWindow();
  if (hwnd == nullptr) {
    return;
  }

  applying_ = true;

  const LONG left = caret_.left;
  const LONG top = caret_.top;
  const LONG right = caret_.right;
  const LONG bottom = caret_.bottom;

  // Some IMEs ignore ImmSetCandidateWindow and follow the system caret.
  ::SetCaretPos(left, bottom);

  HWND imm_hwnd = hwnd;
  HIMC context = ::ImmGetContext(imm_hwnd);
  if (context == nullptr && host_ != nullptr && imm_hwnd != host_) {
    imm_hwnd = host_;
    context = ::ImmGetContext(imm_hwnd);
  }
  if (context == nullptr && view_ != nullptr && imm_hwnd != view_) {
    imm_hwnd = view_;
    context = ::ImmGetContext(imm_hwnd);
  }
  if (context == nullptr) {
    applying_ = false;
    return;
  }

  COMPOSITIONFORM composition = {};
  composition.dwStyle = CFS_POINT;
  composition.ptCurrentPos = {left, top};
  ::ImmSetCompositionWindow(context, &composition);

  CANDIDATEFORM candidate = {};
  candidate.dwIndex = 0;
  candidate.dwStyle = CFS_EXCLUDE;
  candidate.ptCurrentPos = {left, bottom};
  candidate.rcArea = {left, top, right, bottom};
  ::ImmSetCandidateWindow(context, &candidate);

  ::ImmReleaseContext(imm_hwnd, context);
  applying_ = false;
}
