#include "win_screenshot.h"

#include <flutter/encodable_value.h>

#include <windowsx.h>
#include <wincodec.h>

#include <algorithm>
#include <string>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "msimg32.lib")

namespace {

constexpr wchar_t kClassName[] = L"CaoIMScreenshot";
constexpr int kMinSize = 8;

int Scale(int value, int dpi) { return MulDiv(value, dpi, 96); }

std::vector<uint8_t> EncodePng(const uint8_t* pixels, int width, int height,
                               int stride) {
  std::vector<uint8_t> encoded;
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninit = init == S_OK || init == S_FALSE;

  IWICImagingFactory* factory = nullptr;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    if (uninit) CoUninitialize();
    return encoded;
  }

  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    factory->Release();
    if (uninit) CoUninitialize();
    return encoded;
  }

  IWICBitmapEncoder* encoder = nullptr;
  IWICBitmapFrameEncode* frame = nullptr;
  HRESULT hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (SUCCEEDED(hr)) hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
  if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, nullptr);
  if (SUCCEEDED(hr)) hr = frame->Initialize(nullptr);
  if (SUCCEEDED(hr)) hr = frame->SetSize(static_cast<UINT>(width), static_cast<UINT>(height));
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&format);
  if (SUCCEEDED(hr) && format == GUID_WICPixelFormat32bppBGRA) {
    hr = frame->WritePixels(static_cast<UINT>(height), static_cast<UINT>(stride),
                            static_cast<UINT>(stride * height),
                            const_cast<BYTE*>(pixels));
  } else if (SUCCEEDED(hr)) {
    hr = E_FAIL;
  }
  if (SUCCEEDED(hr)) hr = frame->Commit();
  if (SUCCEEDED(hr)) hr = encoder->Commit();

  if (SUCCEEDED(hr)) {
    STATSTG stat{};
    if (SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME)) &&
        stat.cbSize.QuadPart > 0 && stat.cbSize.QuadPart < 64 * 1024 * 1024) {
      const ULONG size = static_cast<ULONG>(stat.cbSize.QuadPart);
      LARGE_INTEGER zero{};
      stream->Seek(zero, STREAM_SEEK_SET, nullptr);
      encoded.resize(size);
      ULONG read = 0;
      if (FAILED(stream->Read(encoded.data(), size, &read)) || read == 0) {
        encoded.clear();
      } else {
        encoded.resize(read);
      }
    }
  }

  if (frame) frame->Release();
  if (encoder) encoder->Release();
  stream->Release();
  factory->Release();
  if (uninit) CoUninitialize();
  return encoded;
}

}  // namespace

WinScreenshot::WinScreenshot(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "caoim/screenshot", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleCall(call, std::move(result)); });

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &WinScreenshot::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_CROSS);
  RegisterClassW(&window_class);
}

WinScreenshot::~WinScreenshot() {
  channel_->SetMethodCallHandler(nullptr);
  if (hwnd_ != nullptr) {
    HWND hwnd = hwnd_;
    hwnd_ = nullptr;
    finished_ = true;
    DestroyWindow(hwnd);
  }
  ReleaseFrame();
  if (font_ != nullptr) {
    DeleteObject(font_);
    font_ = nullptr;
  }
}

void WinScreenshot::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "start") {
    result->NotImplemented();
    return;
  }
  if (busy_) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  busy_ = true;
  finished_ = false;
  const bool opened = Open();
  if (!opened) {
    busy_ = false;
    finished_ = true;
    ReleaseFrame();
  }
  result->Success(flutter::EncodableValue(opened));
}

bool WinScreenshot::Open() {
  ReleaseFrame();
  origin_x_ = GetSystemMetrics(SM_XVIRTUALSCREEN);
  origin_y_ = GetSystemMetrics(SM_YVIRTUALSCREEN);
  width_ = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  height_ = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width_ <= 0 || height_ <= 0) return false;

  HDC screen = GetDC(nullptr);
  if (screen == nullptr) return false;
  HDC memory = CreateCompatibleDC(screen);
  frame_ = CreateCompatibleBitmap(screen, width_, height_);
  shade_ = CreateCompatibleBitmap(screen, 1, 1);
  if (memory == nullptr || frame_ == nullptr || shade_ == nullptr) {
    if (memory != nullptr) DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return false;
  }
  HGDIOBJ previous = SelectObject(memory, frame_);
  BitBlt(memory, 0, 0, width_, height_, screen, origin_x_, origin_y_,
         SRCCOPY | CAPTUREBLT);
  SelectObject(memory, shade_);
  RECT pixel{0, 0, 1, 1};
  HBRUSH black = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(memory, &pixel, black);
  DeleteObject(black);
  SelectObject(memory, previous);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);

  dpi_ = GetDpiForSystem();
  if (dpi_ < 96) dpi_ = 96;
  if (font_ == nullptr) {
    font_ = CreateFontW(-Scale(15, dpi_), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                        L"Microsoft YaHei UI");
  }

  dragging_ = false;
  moved_ = false;
  anchor_ = POINT{0, 0};
  current_ = POINT{0, 0};
  hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"",
                          WS_POPUP | WS_VISIBLE, origin_x_, origin_y_, width_,
                          height_, nullptr, nullptr, GetModuleHandle(nullptr),
                          this);
  if (hwnd_ == nullptr) return false;
  SetWindowPos(hwnd_, HWND_TOPMOST, origin_x_, origin_y_, width_, height_,
               SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd_);
  SetFocus(hwnd_);
  return true;
}

void WinScreenshot::Finish(bool accept) {
  if (finished_) return;
  finished_ = true;
  std::vector<uint8_t> png;
  if (accept) png = EncodeSelection();
  HWND hwnd = hwnd_;
  hwnd_ = nullptr;
  if (hwnd != nullptr) DestroyWindow(hwnd);
  ReleaseFrame();
  busy_ = false;
  Notify(std::move(png), !accept);
}

void WinScreenshot::Notify(std::vector<uint8_t> png, bool cancelled) {
  if (channel_ == nullptr) return;
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("cancelled")] = flutter::EncodableValue(cancelled);
  if (!png.empty() && !cancelled) {
    payload[flutter::EncodableValue("bytes")] =
        flutter::EncodableValue(std::move(png));
  }
  channel_->InvokeMethod("onResult",
                         std::make_unique<flutter::EncodableValue>(payload));
}

void WinScreenshot::ReleaseFrame() {
  if (frame_ != nullptr) {
    DeleteObject(frame_);
    frame_ = nullptr;
  }
  if (shade_ != nullptr) {
    DeleteObject(shade_);
    shade_ = nullptr;
  }
}

RECT WinScreenshot::Selection() const {
  RECT rect{
      std::min(anchor_.x, current_.x),
      std::min(anchor_.y, current_.y),
      std::max(anchor_.x, current_.x),
      std::max(anchor_.y, current_.y),
  };
  rect.left = std::clamp(static_cast<int>(rect.left), 0, width_);
  rect.top = std::clamp(static_cast<int>(rect.top), 0, height_);
  rect.right = std::clamp(static_cast<int>(rect.right), 0, width_);
  rect.bottom = std::clamp(static_cast<int>(rect.bottom), 0, height_);
  return rect;
}

void WinScreenshot::LayoutActions(RECT selection, RECT* cancel, RECT* done) const {
  const int gap = Scale(8, dpi_);
  const int button_w = Scale(76, dpi_);
  const int button_h = Scale(30, dpi_);
  int x = selection.right - button_w * 2 - gap;
  int y = selection.bottom + gap;
  if (y + button_h > height_) y = selection.top - gap - button_h;
  if (y < 0) y = gap;
  if (x < gap) x = gap;
  if (x + button_w * 2 + gap > width_) x = std::max(gap, width_ - button_w * 2 - gap);
  *cancel = RECT{x, y, x + button_w, y + button_h};
  *done = RECT{x + button_w + gap, y, x + button_w * 2 + gap, y + button_h};
}

bool WinScreenshot::Hit(RECT rect, int x, int y) const {
  return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
}

void WinScreenshot::DrawButton(HDC hdc, RECT rect, const wchar_t* text,
                               COLORREF fill) const {
  HBRUSH brush = CreateSolidBrush(fill);
  HGDIOBJ previous = SelectObject(hdc, brush);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, Scale(6, dpi_),
            Scale(6, dpi_));
  SelectObject(hdc, previous);
  DeleteObject(brush);
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, RGB(255, 255, 255));
  DrawTextW(hdc, text, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void WinScreenshot::Paint(HDC hdc) {
  if (frame_ == nullptr) return;
  HDC source = CreateCompatibleDC(hdc);
  HGDIOBJ previous = SelectObject(source, frame_);
  BitBlt(hdc, 0, 0, width_, height_, source, 0, 0, SRCCOPY);

  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 110;
  HGDIOBJ shade_previous = SelectObject(source, shade_);
  const RECT selection = moved_ ? Selection() : RECT{0, 0, 0, 0};
  const int sel_w = selection.right - selection.left;
  const int sel_h = selection.bottom - selection.top;
  const bool has_selection = sel_w >= kMinSize && sel_h >= kMinSize;
  if (!has_selection) {
    AlphaBlend(hdc, 0, 0, width_, height_, source, 0, 0, 1, 1, blend);
  } else {
    if (selection.top > 0) {
      AlphaBlend(hdc, 0, 0, width_, selection.top, source, 0, 0, 1, 1, blend);
    }
    if (selection.bottom < height_) {
      AlphaBlend(hdc, 0, selection.bottom, width_, height_ - selection.bottom,
                 source, 0, 0, 1, 1, blend);
    }
    if (selection.left > 0) {
      AlphaBlend(hdc, 0, selection.top, selection.left, sel_h, source, 0, 0, 1, 1,
                 blend);
    }
    if (selection.right < width_) {
      AlphaBlend(hdc, selection.right, selection.top, width_ - selection.right, sel_h,
                 source, 0, 0, 1, 1, blend);
    }
    SelectObject(source, frame_);
    BitBlt(hdc, selection.left, selection.top, sel_w, sel_h, source, selection.left,
           selection.top, SRCCOPY);
    HPEN pen = CreatePen(PS_SOLID, Scale(2, dpi_), RGB(7, 193, 96));
    HGDIOBJ old_pen = SelectObject(hdc, pen);
    HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(HOLLOW_BRUSH));
    Rectangle(hdc, selection.left, selection.top, selection.right, selection.bottom);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(pen);
  }
  SelectObject(source, shade_previous);
  SelectObject(source, previous);
  DeleteDC(source);

  HGDIOBJ old_font = font_ == nullptr ? nullptr : SelectObject(hdc, font_);
  if (!has_selection) {
    const wchar_t* hint =
        L"\u62D6\u52A8\u9009\u62E9\u533A\u57DF\uFF0CEnter \u5B8C\u6210\uFF0CEsc "
        L"\u53D6\u6D88";
    RECT hint_rect{0, Scale(24, dpi_), width_, Scale(56, dpi_)};
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(255, 255, 255));
    DrawTextW(hdc, hint, -1, &hint_rect, DT_CENTER | DT_SINGLELINE);
  } else if (!dragging_) {
    wchar_t label[32];
    swprintf_s(label, L"%d x %d", sel_w, sel_h);
    RECT label_rect{selection.left, selection.top - Scale(24, dpi_), selection.right,
                    selection.top - Scale(4, dpi_)};
    if (label_rect.top < 0) {
      label_rect.top = selection.top + Scale(4, dpi_);
      label_rect.bottom = label_rect.top + Scale(20, dpi_);
    }
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(255, 255, 255));
    DrawTextW(hdc, label, -1, &label_rect, DT_LEFT | DT_SINGLELINE);
    RECT cancel{};
    RECT done{};
    LayoutActions(selection, &cancel, &done);
    DrawButton(hdc, cancel, L"\u53D6\u6D88", RGB(60, 60, 60));
    DrawButton(hdc, done, L"\u5B8C\u6210", RGB(7, 193, 96));
  }
  if (old_font != nullptr) SelectObject(hdc, old_font);
}

std::vector<uint8_t> WinScreenshot::EncodeSelection() const {
  const RECT selection = Selection();
  const int crop_w = selection.right - selection.left;
  const int crop_h = selection.bottom - selection.top;
  if (frame_ == nullptr || crop_w < kMinSize || crop_h < kMinSize) return {};

  HDC screen = GetDC(nullptr);
  HDC source = CreateCompatibleDC(screen);
  HDC crop_dc = CreateCompatibleDC(screen);
  HBITMAP crop = CreateCompatibleBitmap(screen, crop_w, crop_h);
  if (screen == nullptr || source == nullptr || crop_dc == nullptr || crop == nullptr) {
    if (crop != nullptr) DeleteObject(crop);
    if (crop_dc != nullptr) DeleteDC(crop_dc);
    if (source != nullptr) DeleteDC(source);
    if (screen != nullptr) ReleaseDC(nullptr, screen);
    return {};
  }
  HGDIOBJ old_source = SelectObject(source, frame_);
  HGDIOBJ old_crop = SelectObject(crop_dc, crop);
  BitBlt(crop_dc, 0, 0, crop_w, crop_h, source, selection.left, selection.top, SRCCOPY);
  SelectObject(crop_dc, old_crop);
  SelectObject(source, old_source);

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = crop_w;
  info.bmiHeader.biHeight = -crop_h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  std::vector<uint8_t> pixels(static_cast<size_t>(crop_w) * static_cast<size_t>(crop_h) * 4);
  const int rows = GetDIBits(crop_dc, crop, 0, static_cast<UINT>(crop_h), pixels.data(),
                             &info, DIB_RGB_COLORS);
  DeleteObject(crop);
  DeleteDC(crop_dc);
  DeleteDC(source);
  ReleaseDC(nullptr, screen);
  if (rows == 0) return {};
  for (size_t i = 3; i < pixels.size(); i += 4) pixels[i] = 255;
  return EncodePng(pixels.data(), crop_w, crop_h, crop_w * 4);
}

LRESULT WinScreenshot::Handle(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_NCCREATE:
      return TRUE;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC hdc = BeginPaint(hwnd, &paint);
      Paint(hdc);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_CROSS));
      return TRUE;
    case WM_LBUTTONDOWN: {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      if (moved_ && !dragging_) {
        const RECT selection = Selection();
        RECT cancel{};
        RECT done{};
        LayoutActions(selection, &cancel, &done);
        if (Hit(done, x, y)) {
          Finish(true);
          return 0;
        }
        if (Hit(cancel, x, y)) {
          Finish(false);
          return 0;
        }
      }
      dragging_ = true;
      moved_ = false;
      anchor_ = POINT{x, y};
      current_ = anchor_;
      SetCapture(hwnd);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    case WM_MOUSEMOVE:
      if (dragging_) {
        current_ = POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        moved_ = true;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (dragging_) {
        dragging_ = false;
        current_ = POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ReleaseCapture();
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_RBUTTONUP:
      Finish(false);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        Finish(false);
        return 0;
      }
      if (wparam == VK_RETURN) {
        const RECT selection = Selection();
        if (moved_ && selection.right - selection.left >= kMinSize &&
            selection.bottom - selection.top >= kMinSize) {
          Finish(true);
        }
        return 0;
      }
      return 0;
    case WM_CLOSE:
      Finish(false);
      return 0;
    default:
      return DefWindowProc(hwnd, message, wparam, lparam);
  }
}

LRESULT CALLBACK WinScreenshot::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* created = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* created_self = reinterpret_cast<WinScreenshot*>(created->lpCreateParams);
    if (created_self != nullptr) created_self->hwnd_ = hwnd;
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(created->lpCreateParams));
  }
  auto* self = reinterpret_cast<WinScreenshot*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (self == nullptr) return DefWindowProc(hwnd, message, wparam, lparam);
  return self->Handle(hwnd, message, wparam, lparam);
}
