import Cocoa
import FlutterMacOS
import UserNotifications

/// Dictation apps such as Wispr Flow insert text through accessibility. Flutter's hidden text
/// view accepts that and reports success, but never tells Flutter, so the words vanish. Sending
/// them the way the keyboard does means every text box takes them.
private func forwardInsertedTextToFlutter() {
  guard let textInput = NSClassFromString("FlutterTextInputPlugin") else { return }
  let insert: @convention(block) (NSTextView, NSString?) -> Void = { view, text in
    guard let text else { return }
    view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
  }
  class_replaceMethod(
    textInput,
    NSSelectorFromString("setAccessibilitySelectedText:"),
    imp_implementationWithBlock(insert),
    "v@:@"
  )
}

/// Flutter's Mac engine doesn't pass on Reduce Motion, so the app asks for it here and is told
/// when it changes. Without this every animation would play for someone who turned motion off.
private func shareReduceMotion(with controller: FlutterViewController) -> NSObjectProtocol {
  let channel = FlutterMethodChannel(name: "aie/motion", binaryMessenger: controller.engine.binaryMessenger)
  channel.setMethodCallHandler { call, result in
    if call.method == "get" {
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
  return NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
  ) { _ in
    channel.invokeMethod("changed", arguments: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }
}

/// A long render ends while a person is in another app, so they're told by a notification. macOS asks
/// them once whether that's all right, and nothing is shown if they said no.
private func shareNotifications(with controller: FlutterViewController) -> FlutterMethodChannel {
  let channel = FlutterMethodChannel(name: "aie/notify", binaryMessenger: controller.engine.binaryMessenger)
  channel.setMethodCallHandler { call, result in
    guard call.method == "show", let words = call.arguments as? [String: String] else {
      result(FlutterMethodNotImplemented)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
      guard allowed else { return }
      let content = UNMutableNotificationContent()
      content.title = words["title"] ?? "AI Editor"
      content.body = words["body"] ?? ""
      content.sound = .default
      center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    result(nil)
  }
  return channel
}

class MainFlutterWindow: NSWindow {
  private var notifyChannel: FlutterMethodChannel?
  private var reduceMotionObserver: NSObjectProtocol?
  /// Files dropped on the window go to Flutter as paths, which decides what each one is for. No package
  /// is needed: the window is the drop target, since none of Flutter's views take files.
  private var dropChannel: FlutterMethodChannel?

  private func droppedFiles(_ sender: NSDraggingInfo) -> [String] {
    let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return urls.map { $0.path }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard !droppedFiles(sender).isEmpty else { return [] }
    dropChannel?.invokeMethod("over", arguments: true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    dropChannel?.invokeMethod("over", arguments: false)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return !droppedFiles(sender).isEmpty
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = droppedFiles(sender)
    dropChannel?.invokeMethod("over", arguments: false)
    guard !paths.isEmpty else { return false }
    dropChannel?.invokeMethod("dropped", arguments: paths)
    return true
  }

  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    dropChannel?.invokeMethod("over", arguments: false)
  }

  override func awakeFromNib() {
    forwardInsertedTextToFlutter()
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = "AI Editor"
    self.minSize = NSSize(width: 1180, height: 760)
    // Setting the view controller shrinks the window, so its size has to come after.
    let room = (self.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 920)
    let width = min(1440, room.width)
    let height = min(920, room.height)
    self.setFrame(NSRect(x: room.midX - width / 2, y: room.midY - height / 2, width: width, height: height), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    reduceMotionObserver = shareReduceMotion(with: flutterViewController)
    dropChannel = FlutterMethodChannel(name: "aie/drop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    notifyChannel = shareNotifications(with: flutterViewController)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }
}
