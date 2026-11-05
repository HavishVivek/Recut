import Cocoa
import FlutterMacOS

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

class MainFlutterWindow: NSWindow {
  private var reduceMotionObserver: NSObjectProtocol?

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

    super.awakeFromNib()
  }
}
