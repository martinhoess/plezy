#if os(iOS) || os(tvOS)
  import Flutter
  import Foundation

  /// Answers `com.plezy/icloud_settings` on iOS, iPadOS and tvOS: reads and writes the settings
  /// snapshot that ICloudSettingsSyncService keeps in iCloud's key-value store, and tells Dart when
  /// another device changed it. Needs the `com.apple.developer.ubiquity-kvstore-identifier`
  /// entitlement; the iOS and tvOS apps share one store because they share a bundle identifier.
  final class ICloudSettingsPlugin: NSObject, FlutterPlugin {
    private static let snapshotKey = "settings_snapshot"
    private let channel: FlutterMethodChannel
    private var observer: NSObjectProtocol?

    private init(channel: FlutterMethodChannel) {
      self.channel = channel
      super.init()
      let store = NSUbiquitousKeyValueStore.default
      // Fires when iCloud delivers another device's write, and once after the first download on a
      // fresh install, whose store reads empty until then.
      observer = NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: store,
        queue: .main
      ) { [weak self] note in
        let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int ?? -1
        Self.log("external change, reason \(reason)")
        self?.channel.invokeMethod("changedExternally", arguments: reason)
      }
      // Starts the download; until it lands the store answers from its local copy.
      store.synchronize()
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(
        name: "com.plezy/icloud_settings",
        binaryMessenger: registrar.messenger()
      )
      registrar.addMethodCallDelegate(ICloudSettingsPlugin(channel: channel), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      let store = NSUbiquitousKeyValueStore.default
      switch call.method {
      case "get":
        store.synchronize()
        let snapshot = store.string(forKey: Self.snapshotKey)
        Self.log("get: \(snapshot.map { "\($0.utf8.count) bytes" } ?? "empty")")
        result(snapshot)
      case "set":
        guard let snapshot = call.arguments as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a JSON string", details: nil))
          return
        }
        store.set(snapshot, forKey: Self.snapshotKey)
        let synced = store.synchronize()
        Self.log("set: \(snapshot.utf8.count) bytes, synchronize \(synced)")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    /// stderr reaches `devicectl device process launch --console`, which release builds need.
    private static func log(_ message: String) {
      fputs("[ICloudSettings] \(message)\n", stderr)
    }
  }
#endif
