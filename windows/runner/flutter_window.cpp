#include "flutter_window.h"

#include <optional>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

// Handle global para o hook de teclado de baixo nível e janela principal
static HHOOK g_keyboard_hook = nullptr;
static HWND g_top_level_hwnd = nullptr;

constexpr UINT WM_APP_VOLUME_COMMAND = WM_APP + 101;

/// Procedimento de gancho de teclado de baixo nível (WH_KEYBOARD_LL).
/// Intercepta as teclas de hardware de volume (VK_VOLUME_UP, VK_VOLUME_DOWN, VK_VOLUME_MUTE)
/// ANTES do mixer de áudio do Windows.
/// - Quando o app está em PRIMEIRO PLANO (ativo e visível), suprime o evento do Windows
///   (retornando 1) e envia o comando via MethodChannel para a Smart TV LG.
/// - Quando o app está MINIMIZADO ou em SEGUNDO PLANO, passa o evento adiante via CallNextHookEx,
///   permitindo que o Windows controle o volume do próprio computador normalmente.
static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION) {
    PKBDLLHOOKSTRUCT p = reinterpret_cast<PKBDLLHOOKSTRUCT>(lParam);
    if (p->vkCode == VK_VOLUME_UP || p->vkCode == VK_VOLUME_DOWN || p->vkCode == VK_VOLUME_MUTE) {
      HWND foreground = GetForegroundWindow();
      bool isForeground = false;
      if (foreground != nullptr && g_top_level_hwnd != nullptr) {
        if (!IsIconic(g_top_level_hwnd) && IsWindowVisible(g_top_level_hwnd)) {
          if (foreground == g_top_level_hwnd || GetAncestor(foreground, GA_ROOT) == g_top_level_hwnd) {
            isForeground = true;
          }
        }
      }

      if (isForeground) {
        bool isKeyDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
        if (isKeyDown) {
          PostMessage(g_top_level_hwnd, WM_APP_VOLUME_COMMAND, p->vkCode, 0);
        }
        // Retornar 1 suprime o evento do mixer de áudio do Windows e de todas as outras janelas
        return 1;
      }
    }
  }
  return CallNextHookEx(g_keyboard_hook, nCode, wParam, lParam);
}

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

  // Configura o MethodChannel para comunicação direta com o Flutter
  volume_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "controle_lg/volume_keys",
      &flutter::StandardMethodCodec::GetInstance());

  // Registra o hook de teclado de baixo nível
  g_top_level_hwnd = GetHandle();
  g_keyboard_hook = SetWindowsHookEx(
      WH_KEYBOARD_LL,
      LowLevelKeyboardProc,
      GetModuleHandle(nullptr),
      0);

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
  if (g_keyboard_hook != nullptr) {
    UnhookWindowsHookEx(g_keyboard_hook);
    g_keyboard_hook = nullptr;
  }
  g_top_level_hwnd = nullptr;

  if (volume_channel_) {
    volume_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_APPCOMMAND: {
      DWORD cmd = GET_APPCOMMAND_LPARAM(lparam);
      if (cmd == APPCOMMAND_VOLUME_UP || cmd == APPCOMMAND_VOLUME_DOWN || cmd == APPCOMMAND_VOLUME_MUTE) {
        // Consome para garantir que o Windows não processe
        return TRUE;
      }
      break;
    }
    case WM_APP_VOLUME_COMMAND: {
      if (volume_channel_) {
        if (wparam == VK_VOLUME_UP) {
          volume_channel_->InvokeMethod("volumeUp", nullptr);
        } else if (wparam == VK_VOLUME_DOWN) {
          volume_channel_->InvokeMethod("volumeDown", nullptr);
        } else if (wparam == VK_VOLUME_MUTE) {
          volume_channel_->InvokeMethod("volumeMute", nullptr);
        }
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
