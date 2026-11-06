import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const pictureExtensions = ['png', 'jpg', 'jpeg', 'webp'];
const modelExtensions = ['glb', 'gltf', 'stl', 'obj'];
const videoExtensions = ['mp4', 'mov', 'mkv', 'm4v', 'webm'];

String _extension(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// What dropped files are for: photos and 3D models for new videos, videos to choose a use
/// for, and anything else, which is refused in words.
({List<String> photos, List<String> videos, List<String> other}) sortDropped(List<String> paths) {
  final photos = <String>[], videos = <String>[], other = <String>[];
  for (final path in paths) {
    final extension = _extension(path);
    if (pictureExtensions.contains(extension) || modelExtensions.contains(extension)) {
      photos.add(path);
    } else if (videoExtensions.contains(extension)) {
      videos.add(path);
    } else {
      other.add(path);
    }
  }
  return (photos: photos, videos: videos, other: other);
}

/// Files dragged over and dropped on the window. The window itself takes them, in
/// MainFlutterWindow.swift, because none of Flutter's views do.
class Drops extends ChangeNotifier {
  Drops._() {
    _channel.setMethodCallHandler(_heard);
  }

  static const _channel = MethodChannel('aie/drop');
  static final instance = Drops._();

  bool over = false;
  void Function(List<String> paths)? onDropped;

  Future<void> _heard(MethodCall call) async {
    if (call.method == 'over') hover(call.arguments == true);
    if (call.method == 'dropped') drop(((call.arguments as List?) ?? const []).cast<String>());
  }

  void hover(bool value) {
    if (over == value) return;
    over = value;
    notifyListeners();
  }

  void drop(List<String> paths) {
    hover(false);
    if (paths.isNotEmpty) onDropped?.call(paths);
  }
}
