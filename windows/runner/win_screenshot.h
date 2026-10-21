#ifndef RUNNER_WIN_SCREENSHOT_H_
#define RUNNER_WIN_SCREENSHOT_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <vector>

#include <windows.h>

namespace flutter {
class BinaryMessenger;
class EncodableValue;
}  // namespace flutter

// Freezes the desktop, lets the user drag a region, and returns a PNG.
class WinScreenshot {
 public:
  explicit WinScreenshot(flutter::BinaryMessenger* messenger);
  ~WinScreenshot();

  WinScreenshot(const WinScreenshot&) = delete;
  WinScreenshot& operator=(const WinScreenshot&) = delete;

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool Open();
  void Finish(bool accept);
  void Notify(std::vector<uint8_t> png, bool cancelled);
  void ReleaseFrame();
  RECT Selection() const;
  void LayoutActions(RECT selection, RECT* cancel, RECT* done) const;
  bool Hit(RECT rect, int x, int y) const;
  void Paint(HDC hdc);
  void DrawButton(HDC hdc, RECT rect, const wchar_t* text, COLORREF fill) const;
  std::vector<uint8_t> EncodeSelection() const;
  LRESULT Handle(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND hwnd_ = nullptr;
  HBITMAP frame_ = nullptr;
  HBITMAP shade_ = nullptr;
  HFONT font_ = nullptr;
  int origin_x_ = 0;
  int origin_y_ = 0;
  int width_ = 0;
  int height_ = 0;
  int dpi_ = 96;
  bool busy_ = false;
  bool finished_ = true;
  bool dragging_ = false;
  bool moved_ = false;
  POINT anchor_{};
  POINT current_{};
};

#endif  // RUNNER_WIN_SCREENSHOT_H_
