import AVFoundation
import Foundation
import Flutter
import XCTest

@testable import Runner

private final class TvosControllablePropertyCore: MpvPlayerCoreBase {
  var nextResult: Result<Void, Error>?

  override func setPropertyAsync(
    _ name: String,
    value: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let nextResult else {
      XCTFail("A controlled property result was not configured")
      return
    }
    self.nextResult = nil
    completion(nextResult)
  }
}

private final class TvosRecordingAudioOutputCore: MpvPlayerCoreBase {
  var currentAo: String? = "audiounit"
  var audioChannels: String? = "auto-safe"
  var outputPorts = ["hdmi-out"]
  var commands: [[String]] = []
  /// Counted and fulfilled by each route check, which reads the ports once.
  var routeChecks = 0
  var routeChecked: XCTestExpectation?
  private var observing = false

  override var audioRouteSettleDelay: DispatchTimeInterval { .milliseconds(100) }

  override var currentAudioOutputPorts: [String] {
    if observing {
      routeChecks += 1
      routeChecked?.fulfill()
    }
    return outputPorts
  }

  override func observeAudioRoute() {
    super.observeAudioRoute()
    observing = true
  }

  override func getPropertyAsync(_ name: String, completion: @escaping (Result<String?, Error>) -> Void) {
    switch name {
    case "current-ao": completion(.success(currentAo))
    case "audio-channels": completion(.success(audioChannels))
    default: completion(.success(nil))
    }
  }

  override func commandAsync(_ args: [String], completion: @escaping (Result<Int64?, Error>) -> Void) {
    commands.append(args)
    completion(.success(nil))
  }
}

private final class TvosRecordingMpvPlugin: MpvPluginShared {
  var coreBase: MpvPlayerCoreBase?
  var eventSink: FlutterEventSink?
  var nameToId: [String: Int] = [:]

  init(core: MpvPlayerCoreBase?) {
    coreBase = core
  }

  func setPlayerVisible(_ visible: Bool, restoreOnWindowVisible: Bool) {}
  func updatePlayerFrame() {}
  func setPlayerVideoZoom(_ scale: Double) {}
  func didSetPauseProperty(value: String) {}
}

final class MpvPlayerContractTests: XCTestCase {
  func testSharedTransportEmitsSourceQualifiedPayloads() {
    let plugin = TvosRecordingMpvPlugin(core: nil)
    plugin.nameToId["time-pos"] = 27
    var messages: [Any?] = []
    plugin.eventSink = { messages.append($0) }
    let sourceId = Int64.max - 7

    plugin.onPropertyChange(name: "time-pos", value: 12.5, sourceId: sourceId)
    plugin.onPropertyChange(name: "time-pos", value: nil, sourceId: nil)
    plugin.onEvent(
      name: "playback-restart",
      data: ["sourceId": sourceId, "positionSeconds": 12.5]
    )

    XCTAssertEqual(messages.count, 3)
    guard
      let sourcedProperty = messages[0] as? [Any?],
      let preStartProperty = messages[1] as? [Any?],
      let lifecycleEvent = messages[2] as? [String: Any],
      let lifecycleData = lifecycleEvent["data"] as? [String: Any]
    else {
      return XCTFail("Expected property triples and a lifecycle event map")
    }
    XCTAssertEqual(sourcedProperty.count, 3)
    XCTAssertEqual(sourcedProperty[0] as? Int, 27)
    XCTAssertEqual(sourcedProperty[1] as? Double, 12.5)
    XCTAssertEqual(sourcedProperty[2] as? Int64, sourceId)
    XCTAssertEqual(preStartProperty.count, 3)
    XCTAssertNil(preStartProperty[1])
    XCTAssertNil(preStartProperty[2])
    XCTAssertEqual(lifecycleEvent["name"] as? String, "playback-restart")
    XCTAssertEqual(lifecycleData["sourceId"] as? Int64, sourceId)
    XCTAssertEqual(lifecycleData["positionSeconds"] as? Double, 12.5)
  }

  func testSharedSetPropertyMapsLifecycleCancellationAsNotInitialized() {
    let core = TvosControllablePropertyCore()
    let plugin = TvosRecordingMpvPlugin(core: core)
    core.nextResult = .failure(MpvLifecycleUnavailableError("controlled cancellation"))

    let results = invokeSetProperty(plugin)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual((results[0] as? FlutterError)?.code, "NOT_INITIALIZED")
  }

  func testSharedSetPropertyKeepsGenuineRejectionNonRecoverable() {
    let core = TvosControllablePropertyCore()
    let plugin = TvosRecordingMpvPlugin(core: core)
    core.nextResult = .failure(
      NSError(
        domain: "MpvPlayerContractTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "controlled rejection"]
      ))

    let results = invokeSetProperty(plugin)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual((results[0] as? FlutterError)?.code, "SET_PROPERTY_FAILED")
  }

  func testNominalRefreshRateSnapsContainerRatesWithinOnePercent() {
    // 29.97i capture: container-fps 29.95784 doubled on field output.
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(59.91568), 59.94, accuracy: 1e-9)
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(29.95784 * 2), 59.94, accuracy: 1e-9)
    // MKV with a 42 ms DefaultDuration (#2302): nearer 23.976 than 24.
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(23.8095), 23.976, accuracy: 1e-9)
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(59.94006), 59.94, accuracy: 1e-9)
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(119.88), 119.88, accuracy: 1e-9)
  }

  func testNominalRefreshRateLeavesExactAndOutOfBandRatesUntouched() {
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(25), 25)
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(27), 27)
    XCTAssertEqual(MpvPlayerCoreBase.nominalRefreshRate(0), 0)
  }

  func testConnectingAirPodsReloadsAudiounitOutput() {
    let core = observingAudioRouteCore()

    core.outputPorts = ["airpods-a2dp"]
    // Posted without a previous route: the check does not depend on one.
    postRouteChange(core, reasons: [.newDeviceAvailable])

    XCTAssertEqual(core.commands, [["ao-reload"]])
  }

  func testDisconnectingAirPodsReloadsBackToHdmi() {
    let core = observingAudioRouteCore()
    core.outputPorts = ["airpods-a2dp"]
    postRouteChange(core, reasons: [.newDeviceAvailable])

    core.outputPorts = ["hdmi-out"]
    postRouteChange(core, reasons: [.oldDeviceUnavailable])

    XCTAssertEqual(core.commands, [["ao-reload"], ["ao-reload"]])
  }

  func testReasonsBeyondDeviceChangesStillReloadOnNewPorts() {
    for reason: AVAudioSession.RouteChangeReason in [.override, .routeConfigurationChange, .categoryChange] {
      let core = observingAudioRouteCore()

      core.outputPorts = ["airpods-a2dp"]
      postRouteChange(core, reasons: [reason])

      XCTAssertEqual(core.commands, [["ao-reload"]], "reason \(reason.rawValue)")
    }
  }

  func testBurstOfRouteChangesReloadsOnce() {
    let core = observingAudioRouteCore()

    // The ports pass through an empty route before the AirPods settle.
    postRouteChange(core, reasons: [.oldDeviceUnavailable, .newDeviceAvailable, .routeConfigurationChange]) {
      core.outputPorts = $0 < 2 ? [] : ["airpods-a2dp"]
    }
    // Checks the burst failed to cancel would be due by now.
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    core.queue.sync {}

    XCTAssertEqual(core.routeChecks, 1)
    XCTAssertEqual(core.commands, [["ao-reload"]])
  }

  func testRouteChangesOnTheSamePortsKeepAudioOutput() {
    let core = observingAudioRouteCore()
    core.outputPorts = ["airpods-a2dp"]
    postRouteChange(core, reasons: [.newDeviceAvailable])

    // The category and activation changes the reloaded output makes itself.
    postRouteChange(core, reasons: [.categoryChange, .routeConfigurationChange])

    XCTAssertEqual(core.commands, [["ao-reload"]])
  }

  func testChannelLimitsReloadExceptStereo() {
    for (channels, reloads) in [("auto-safe", true), ("stereo,5.1", true), ("stereo", false)] {
      let core = observingAudioRouteCore()
      core.audioChannels = channels

      core.outputPorts = ["airpods-a2dp"]
      postRouteChange(core, reasons: [.newDeviceAvailable])

      XCTAssertEqual(core.commands, reloads ? [["ao-reload"]] : [], "audio-channels \(channels)")
    }
  }

  func testRouteChangeLeavesOtherAudioOutputsAlone() {
    for ao in ["avfoundation", "spatial", nil] as [String?] {
      let core = observingAudioRouteCore()
      core.currentAo = ao

      core.outputPorts = ["airpods-a2dp"]
      postRouteChange(core, reasons: [.newDeviceAvailable])

      XCTAssertEqual(core.commands, [], "current-ao \(ao ?? "none")")
    }
  }

  func testDisposedCoreIgnoresPendingAndLaterRouteChanges() {
    let core = observingAudioRouteCore()
    core.outputPorts = ["airpods-a2dp"]
    let pending = expectation(description: "no route check")
    pending.isInverted = true
    core.routeChecked = pending

    NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
    core.disposeSharedState(destroySynchronously: true)
    NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)

    wait(for: [pending], timeout: 0.5)
    XCTAssertEqual(core.commands, [])
  }

  private func observingAudioRouteCore() -> TvosRecordingAudioOutputCore {
    let core = TvosRecordingAudioOutputCore()
    core.observeAudioRoute()
    addTeardownBlock { core.disposeSharedState(destroySynchronously: true) }
    return core
  }

  /// Posts one notification per reason, back to back, then waits for the one
  /// route check they settle into and for the reload it may issue.
  private func postRouteChange(
    _ core: TvosRecordingAudioOutputCore,
    reasons: [AVAudioSession.RouteChangeReason],
    beforeEach: (Int) -> Void = { _ in }
  ) {
    let checked = expectation(description: "route check")
    // A route change the system posts meanwhile only adds a check.
    checked.assertForOverFulfill = false
    core.routeChecked = checked
    for (index, reason) in reasons.enumerated() {
      beforeEach(index)
      NotificationCenter.default.post(
        name: AVAudioSession.routeChangeNotification, object: nil,
        userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }
    wait(for: [checked], timeout: 2)
    core.routeChecked = nil
    // The check runs on the core's queue.
    core.queue.sync {}
  }

  private func invokeSetProperty(_ plugin: TvosRecordingMpvPlugin) -> [Any?] {
    var results: [Any?] = []
    plugin.handleSetProperty(
      call: FlutterMethodCall(
        methodName: "setProperty",
        arguments: ["name": "volume", "value": "50"]
      )
    ) {
      results.append($0)
    }
    return results
  }
}
