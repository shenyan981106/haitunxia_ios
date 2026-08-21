import UIKit
import Flutter
import StoreKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, SKRequestDelegate {
  /// 苹果 IAP 凭证读取通道的待回调结果(刷新凭证期间暂存)
  private var pendingReceiptResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // ==================== 苹果 IAP:appStoreReceipt 读取通道 ====================
    // 会员开通内购凭证校验接口需要 App 端内购凭证包(StoreKit 的 appStoreReceipt)
    // 的 base64 字符串,Dart 侧插件不暴露该文件,故在此提供原生通道。
    if let controller = window?.rootViewController as? FlutterViewController {
      let iapChannel = FlutterMethodChannel(
        name: "app.haitunxia.com/iap",
        binaryMessenger: controller.binaryMessenger)
      iapChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "APP_DELEGATE_NIL",
                              message: "AppDelegate 已释放",
                              details: nil))
          return
        }
        if call.method == "getReceiptData" {
          self.getReceiptData(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 读取内购凭证 base64;凭证文件不存在时(sandbox 首次购买常见)先刷新再读
  private func getReceiptData(result: @escaping FlutterResult) {
    if let data = receiptData() {
      result(data.base64EncodedString())
      return
    }
    pendingReceiptResult = result
    let refreshRequest = SKReceiptRefreshRequest()
    refreshRequest.delegate = self
    refreshRequest.start()
  }

  /// 读取 Bundle.main.appStoreReceiptURL 指向的凭证文件内容
  private func receiptData() -> Data? {
    guard let url = Bundle.main.appStoreReceiptURL else { return nil }
    return try? Data(contentsOf: url)
  }

  // MARK: - SKRequestDelegate

  func requestDidFinish(_ request: SKRequest) {
    DispatchQueue.main.async {
      guard let result = self.pendingReceiptResult else { return }
      self.pendingReceiptResult = nil
      if let data = self.receiptData() {
        result(data.base64EncodedString())
      } else {
        result(FlutterError(code: "NO_RECEIPT",
                            message: "appStoreReceipt 读取失败",
                            details: nil))
      }
    }
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    DispatchQueue.main.async {
      guard let result = self.pendingReceiptResult else { return }
      self.pendingReceiptResult = nil
      result(FlutterError(code: "REFRESH_FAILED",
                          message: error.localizedDescription,
                          details: nil))
    }
  }
}
