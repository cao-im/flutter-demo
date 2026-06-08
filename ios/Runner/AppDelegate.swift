import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private let KEEP_ALIVE_CHANNEL = "com.clb.caoim/keep_alive"
  private var audioPlayer: AVAudioPlayer?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 注册IM保活MethodChannel（需要在engine初始化后注册，延迟到didInitializeImplicitFlutterEngine中）
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 注册IM保活MethodChannel
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: KEEP_ALIVE_CHANNEL,
      binaryMessenger: engineBridge.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleKeepAliveCall(call: call, result: result)
    }
  }

  /// 处理来自Flutter的保活方法调用
  private func handleKeepAliveCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startKeepAlive":
      startBackgroundKeepAlive()
      result(true)
    case "stopKeepAlive":
      stopBackgroundKeepAlive()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 启动iOS后台保活：使用 AudioSession + 静音音频 + 后台任务
  func startBackgroundKeepAlive() {
    // 1. 配置Audio Session为播放模式（关键：让系统认为APP在播放音频）
    do {
      try AVAudio.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers]
      )
      try AVAudio.sharedInstance().setActive(true)
    } catch {
      print("[IMKeepAlive] AudioSession配置失败: \(error)")
    }

    // 2. 播放静音音频（保持Audio Session活跃）
    playSilentAudio()

    // 3. 注册后台任务（延长后台运行时间）
    beginBackgroundTask()

    print("[IMKeepAlive] iOS后台保活已启动")
  }

  /// 停止iOS后台保活
  func stopBackgroundKeepAlive() {
    // 停止静音音频
    audioPlayer?.stop()
    audioPlayer = nil

    // 停用Audio Session
    do {
      try AVAudio.sharedInstance().setActive(false)
    } catch {
      print("[IMKeepAlive] AudioSession停用失败: \(error)")
    }

    // 结束后台任务
    endBackgroundTask()

    print("[IMKeepAlive] iOS后台保活已停止")
  }

  /// 播放静音音频文件以维持Audio Session活跃
  private func playSilentAudio() {
    guard let url = Bundle.main.url(forResource: "silence", withExtension: "mp3") else {
      // 如果没有静音文件，生成一个静音的PCM数据来创建player
      print("[IMKeepAlive] 未找到silence.mp3，尝试使用内存数据")
      createSilentAudioInMemory()
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = -1 // 无限循环
      audioPlayer?.volume = 0.0       // 静音
      audioPlayer?.play()
      print("[IMKeepAlive] 静音音频播放已启动")
    } catch {
      print("[IMKeepAlive] 静音音频播放失败: \(error)")
    }
  }

  /// 在内存中创建静音音频数据（无需外部文件）
  private func createSilentAudioInMemory() {
    // 创建1秒的静音PCM数据（44100Hz, 16bit, 单声道 = 88200字节）
    let sampleRate: UInt32 = 44100
    let silenceData = Data(count: Int(sampleRate * 2)) // 1秒静音

    do {
      audioPlayer = try AVAudioPlayer(data: silenceData)
      audioPlayer?.numberOfLoops = -1
      audioPlayer?.volume = 0.0
      audioPlayer?.play()
      print("[IMKeepAlive] 内存静音音频已启动")
    } catch {
      print("[IMKeepAlive] 内存静音音频创建失败: \(error)")
    }
  }

  /// 开始后台任务
  private func beginBackgroundTask() {
    endBackgroundTask() // 先结束已有的

    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IMKeepAlive") { [weak self] in
      // 后台任务即将过期时尝试续期
      self?.endBackgroundTask()
      self?.beginBackgroundTask()
    }

    if backgroundTask == .invalid {
      print("[IMKeepAlive] 后台任务注册失败")
    } else {
      print("[IMKeepAlive] 后台任务已注册: \(backgroundTask.rawValue)")
    }
  }

  /// 结束后台任务
  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  /// APP进入后台时重新激活保活
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    // 确保后台保活仍然生效
    if audioPlayer != nil || backgroundTask != .invalid {
      beginBackgroundTask()
    }
  }

  /// APP回到前台时可以适当调整策略
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    // 回到前台后确保Audio Session状态正确
    if audioPlayer != nil {
      do {
        try AVAudio.sharedInstance().setActive(true)
      } catch {
        print("[IMKeepAlive] 前台恢复AudioSession失败: \(error)")
      }
    }
  }
}
