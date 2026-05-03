import UIKit
import Flutter
import GoogleMaps
import FirebaseCore
import Network
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let netMonitor = NWPathMonitor()
  private let netQueue = DispatchQueue(label: "net.monitor.queue")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // =========================
    // 1) gRPC / Firebase debug (قبل تسجيل البلجنز)
    // =========================
    #if DEBUG
    // gRPC tracing: يكشف السبب الحقيقي وراء WriteStream "Internal"
    // أمثلة: TLS handshake, HTTP2 RST_STREAM, transport_security, connectivity_state
    setenv("GRPC_VERBOSITY", "DEBUG", 1)
    setenv("GRPC_TRACE", "connectivity_state,http,transport_security,handshaker,transport", 1)

    // Firebase logger (يساعد في طباعة تفاصيل إضافية)
    FirebaseConfiguration.shared.setLoggerLevel(.max)

    NSLog("🧪 [DIAG] GRPC tracing enabled (DEBUG)")
    NSLog("🧪 [DIAG] iOS=%@ device=%@",
          UIDevice.current.systemVersion,
          UIDevice.current.model)
    #endif

    // =========================
    // 2) Network diagnostics (يرجع سبب دقيق: interface/proxy/ipv6/captive)
    // =========================
    startNetworkDiagnostics()

    // =========================
    // 3) Google Maps Key
    // =========================
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("⚠️ [GoogleMaps] Missing GMSApiKey in Info.plist")
    }

    // =========================
    // 4) Plugins
    // =========================
    GeneratedPluginRegistrant.register(with: self)

    // =========================
    // 5) Offer Code Redemption (يدعم iOS 14+ مع StoreKit1 و iOS 16+ مع StoreKit2)
    // =========================
    setupOfferCodeRedemptionChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Offer Code Redemption Channel (Flutter -> iOS)

  private func setupOfferCodeRedemptionChannel() {
    // لازم يكون نفس الاسم الموجود في Flutter
    // channel: "wazen_iap/offer_code"
    // method:  "presentCodeRedemptionSheet"
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("⚠️ [OfferCode] rootViewController is not FlutterViewController; cannot register channel.")
      return
    }

    let channel = FlutterMethodChannel(
      name: "wazen_iap/offer_code",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }

      switch call.method {
      case "presentCodeRedemptionSheet":
        self.presentOfferCodeRedeemSheet(result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NSLog("✅ [OfferCode] MethodChannel registered: wazen_iap/offer_code")
  }

  private func presentOfferCodeRedeemSheet(result: @escaping FlutterResult) {
    // iOS 16+ (StoreKit 2): AppStore.presentOfferCodeRedeemSheet(in:) async throws
    if #available(iOS 16.0, *) {
      guard let scene = currentWindowScene() else {
        result(FlutterError(
          code: "NO_SCENE",
          message: "Could not find an active UIWindowScene to present the redeem sheet.",
          details: nil
        ))
        return
      }

      Task { @MainActor in
        do {
          try await AppStore.presentOfferCodeRedeemSheet(in: scene)
          result(nil)
        } catch {
          result(FlutterError(
            code: "REDEEM_FAILED",
            message: "Failed to present redeem sheet: \(error)",
            details: nil
          ))
        }
      }
      return
    }

    // iOS 14–15 (StoreKit 1): SKPaymentQueue.presentCodeRedemptionSheet()
    if #available(iOS 14.0, *) {
      DispatchQueue.main.async {
        SKPaymentQueue.default().presentCodeRedemptionSheet()
        result(nil)
      }
      return
    }

    // iOS 13 وأقدم: ما فيه sheet داخل التطبيق — نفتح صفحة الاستبدال في App Store كحل بديل
    openRedeemPageFallback()
    result(FlutterError(
      code: "UNAVAILABLE",
      message: "In-app offer code redemption requires iOS 14+. Opened App Store redeem page instead.",
      details: nil
    ))
  }

  private func currentWindowScene() -> UIWindowScene? {
    // الأفضل: foregroundActive scene
    let scenes = UIApplication.shared.connectedScenes
    if let active = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
      return active
    }
    // fallback: أي scene
    return scenes.first as? UIWindowScene
  }

  private func openRedeemPageFallback() {
    // صفحة الاستبدال العامة (قد تفتح App Store أو Safari حسب النظام)
    if let url = URL(string: "https://apps.apple.com/redeem") {
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    }
  }

  // MARK: - Network diagnostics

  private func startNetworkDiagnostics() {
    // يطبع تغيّرات الشبكة + نوع الاتصال (WiFi/Cellular) + هل فيها Proxy/Captive بشكل غير مباشر
    netMonitor.pathUpdateHandler = { path in
      let status = (path.status == .satisfied) ? "satisfied" : "unsatisfied"
      let expensive = path.isExpensive ? "true" : "false"
      let constrained = path.isConstrained ? "true" : "false"

      var ifaces: [String] = []
      if path.usesInterfaceType(.wifi) { ifaces.append("wifi") }
      if path.usesInterfaceType(.cellular) { ifaces.append("cellular") }
      if path.usesInterfaceType(.wiredEthernet) { ifaces.append("ethernet") }
      if path.usesInterfaceType(.loopback) { ifaces.append("loopback") }

      NSLog("🧪 [NET] status=%@ ifaces=%@ expensive=%@ constrained=%@",
            status, ifaces.joined(separator: ","), expensive, constrained)
    }

    netMonitor.start(queue: netQueue)
  }

  deinit {
    netMonitor.cancel()
  }
}

