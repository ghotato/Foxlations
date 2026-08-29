#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "jvm_bridge.h"

namespace {

// Heap payload carried across the thread hop as the WM_APP LPARAM. The platform
// thread takes ownership and deletes it after replying.
struct JvmReply {
  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  bool ok = false;
  std::string value;       // JSON result on success
  std::string error_code;  // set when !ok
  std::string error_msg;
};

}  // namespace

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

  SetUpJvmChannel();

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetUpJvmChannel() {
  jvm_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "foxlations/jvm",
          &flutter::StandardMethodCodec::GetInstance());

  const HWND hwnd = GetHandle();

  jvm_channel_->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();

        if (method == "probe") {
          result->Success(flutter::EncodableValue(foxjvm::IsAvailable()));
          return;
        }

        if (method != "invoke" && method != "warmup") {
          result->NotImplemented();
          return;
        }

        // Extract the String argument BEFORE leaving the platform thread; the
        // MethodCall is only valid for the duration of this callback.
        std::string request;
        if (method == "invoke") {
          const auto* arg = std::get_if<std::string>(call.arguments());
          if (!arg) {
            result->Error("bad_args", "invoke expects a single String argument");
            return;
          }
          request = *arg;
        }

        // MethodResult is single-use; move it into a shared_ptr owned by the
        // worker until the reply is posted back to the platform thread.
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> shared(
            result.release());

        std::thread([hwnd, method, request, shared]() mutable {
          auto reply = std::make_unique<JvmReply>();
          reply->result = shared;

          // === The slow JNI work runs here, OFF the platform/UI thread. ===
          if (method == "warmup") {
            std::string err;
            reply->ok = foxjvm::Warmup(&err);
            reply->value = "{\"ok\":true}";
            if (!reply->ok) {
              reply->error_code = "jvm_init";
              reply->error_msg = err;
            }
          } else {  // "invoke"
            std::string err;
            std::string out = foxjvm::Invoke(request, &err);
            reply->ok = err.empty();
            if (reply->ok) {
              reply->value = std::move(out);
            } else {
              reply->error_code = "jvm_invoke";
              reply->error_msg = err;
            }
          }

          JvmReply* raw = reply.release();
          if (!PostMessage(hwnd, kJvmReplyMessage, 0,
                           reinterpret_cast<LPARAM>(raw))) {
            delete raw;
          }
        }).detach();
      });
}

void FlutterWindow::OnDestroy() {
  if (jvm_channel_) {
    jvm_channel_->SetMethodCallHandler(nullptr);
    jvm_channel_ = nullptr;
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
  // Deliver a JVM reply on the platform thread (this WndProc runs on the
  // message-pump thread, where MethodResult must be used).
  if (message == kJvmReplyMessage) {
    std::unique_ptr<JvmReply> reply(reinterpret_cast<JvmReply*>(lparam));
    if (reply && reply->result) {
      if (reply->ok) {
        reply->result->Success(flutter::EncodableValue(reply->value));
      } else {
        reply->result->Error(reply->error_code, reply->error_msg);
      }
    }
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

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
