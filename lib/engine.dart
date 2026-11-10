import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The repository holding the Python engine, for a developer's build. A packaged app carries its own.
const repoPath = String.fromEnvironment(
  'AIE_REPO',
  defaultValue: '/Users/cratebind/Developer/AiEditor-app',
);

/// GUI apps don't inherit the shell's PATH, so the Homebrew path is tried first.
String get _uv {
  const homebrew = '/opt/homebrew/bin/uv';
  return File(homebrew).existsSync() ? homebrew : 'uv';
}

/// Inside a packaged app the engine sits beside it, in Contents/Resources/engine, with its own Python.
String? get bundledEngine {
  final contents = File(Platform.resolvedExecutable).parent.parent.path;
  final python = '$contents/Resources/engine/python/bin/python3';
  return File(python).existsSync() ? python : null;
}

/// The bundled tools come first, then the system's, then Homebrew's for anything a person added.
Map<String, String> bundledEnvironment(String python) {
  final resources = File(python).parent.parent.parent.parent.path;
  return {
    ...Platform.environment,
    'PATH': ['$resources/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin', '/opt/homebrew/bin', '/usr/local/bin'].join(':'),
    'AIE_BUNDLE': resources,
  };
}

typedef Json = Map<String, dynamic>;

/// A problem the engine put into words, ready to show a person.
class EngineError implements Exception {
  EngineError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything the app asks of the engine. Tests stand in for it.
abstract class Api {
  Future<List<Json>> connections();
  Future<Json> projects();
  Future<Json> createProject(String name, {String? location, String? footage});
  Future<Json> inspectFolder(String path);
  Future<Json> openProject(String path);
  Future<void> closeProject();
  Future<Json> state();
  Future<Json> plan(String id);
  Future<String> start(String action, Json body);
  Future<Json> job(String id);
  Future<void> cancel(String plan);
  Future<String> reviewPage();
  Future<Json> settings();
  Future<Json> setDefaultModel(String name);
  Future<Json> changeExtensions(Json body);
  Future<List<Json>> searchModels(String words);
  Future<Json> modelFiles(String repo);
  Future<Json> downloadModel(String repo, String? tag);
  Future<Json> modelDownload();
  Future<Json> cancelModelDownload();
  Future<Json> addLicense(String key);
  Future<Json> changeBrand(Json body);
  Future<Json> setup();
  Future<Json> setupAction(String action, [Json body = const {}]);
  Future<Json> removeLicense();
  Future<Json> account(String op, [Json body = const {}]);
  Future<Json> setOnboarded(bool done);
  Future<Json> chat();
  Future<void> stopReply();
}

class Engine implements Api {
  Engine._(this._process, this._port, this._token);

  final Process _process;
  final int _port;
  final String _token;
  final HttpClient _http = HttpClient();

  /// Starts the engine and reads its one line of port and token from stdout.
  static Future<Engine> launch() async {
    final bundled = bundledEngine;
    // -I keeps the bundled Python to itself: no user site-packages and no PYTHON* settings from outside.
    final process = bundled != null
        ? await Process.start(bundled, ['-I', '-m', 'aie.server'], environment: bundledEnvironment(bundled), includeParentEnvironment: false)
        : await Process.start(_uv, ['run', '--directory', repoPath, 'python', '-m', 'aie.server']);
    unawaited(process.stderr.drain<void>());
    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 60));
    final hello = jsonDecode(line) as Json;
    return Engine._(process, hello['port'] as int, hello['token'] as String);
  }

  Future<Json> _call(String method, String path, [Json? body]) async {
    final uri = Uri.parse('http://127.0.0.1:$_port$path');
    final request = await _http.openUrl(method, uri);
    request.headers.set('Authorization', 'Bearer $_token');
    if (body != null) {
      // The engine reads Content-Length. Without one this goes out chunked and arrives empty.
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final reply = await request.close();
    final text = await reply.transform(utf8.decoder).join();
    final json = jsonDecode(text) as Json;
    if (reply.statusCode >= 400) {
      throw EngineError(json['error'] as String? ?? 'Engine error');
    }
    return json;
  }

  @override
  Future<List<Json>> connections() async =>
      ((await _call('GET', '/status'))['connections'] as List).cast<Json>();

  @override
  Future<Json> projects() => _call('GET', '/projects');

  @override
  Future<Json> createProject(String name, {String? location, String? footage}) =>
      _call('POST', '/projects', {'name': name, 'location': location, 'footage': footage});

  @override
  Future<Json> inspectFolder(String path) =>
      _call('POST', '/folders/inspect', {'path': path});

  @override
  Future<Json> openProject(String path) =>
      _call('POST', '/projects/open', {'path': path});

  @override
  Future<void> closeProject() => _call('POST', '/project/close', {});

  @override
  Future<Json> state() => _call('GET', '/project');

  @override
  Future<Json> plan(String id) => _call('GET', '/project/plans/$id');

  @override
  Future<String> start(String action, Json body) async =>
      (await _call('POST', '/project/do/$action', body))['job'] as String;

  @override
  Future<Json> job(String id) => _call('GET', '/jobs/$id');

  @override
  Future<void> cancel(String plan) =>
      _call('POST', '/project/cancel', {'plan': plan});

  @override
  Future<String> reviewPage() async =>
      (await _call('POST', '/project/review-page', {}))['url'] as String;

  @override
  Future<Json> settings() => _call('GET', '/settings');

  @override
  Future<Json> setDefaultModel(String name) =>
      _call('POST', '/settings', {'default_model': name});

  @override
  Future<Json> changeExtensions(Json body) => _call('POST', '/extensions', body);

  @override
  Future<List<Json>> searchModels(String words) async =>
      ((await _call('POST', '/models/search', {'words': words}))['results'] as List).cast<Json>();

  @override
  Future<Json> modelFiles(String repo) => _call('POST', '/models/files', {'repo': repo});

  @override
  Future<Json> downloadModel(String repo, String? tag) =>
      _call('POST', '/models/download', {'repo': repo, 'tag': tag});

  @override
  Future<Json> modelDownload() => _call('GET', '/models/download');

  @override
  Future<Json> cancelModelDownload() => _call('POST', '/models/download/cancel', {});

  @override
  Future<Json> addLicense(String key) => _call('POST', '/license', {'key': key});

  @override
  Future<Json> changeBrand(Json body) => _call('POST', '/brand', body);

  @override
  Future<Json> setup() => _call('GET', '/setup');

  @override
  Future<Json> setupAction(String action, [Json body = const {}]) => _call('POST', '/setup/$action', body);

  @override
  Future<Json> removeLicense() => _call('POST', '/license/remove', {});

  @override
  Future<Json> account(String op, [Json body = const {}]) => _call('POST', '/account/$op', body);

  @override
  Future<Json> setOnboarded(bool done) => _call('POST', '/onboarded', {'done': done});

  @override
  Future<Json> chat() => _call('GET', '/project/chat');

  @override
  Future<void> stopReply() => _call('POST', '/project/chat/stop', {});

  /// Closing stdin is what tells the engine to exit.
  Future<void> stop() async {
    await _process.stdin.close();
    _http.close(force: true);
  }
}
