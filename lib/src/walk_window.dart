import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'walk_panel.dart';

/// Whether the walk's panel has a window of its own, and how large it was made: kept in the walk's
/// folder, so the interface starts again as it was left. Where the window
/// stood is not kept: the desktop decides that, and on Wayland does not tell.
@immutable
class WalkWindowLayout {
  /// Constructor taking whether it is detached, and the window's size.
  const WalkWindowLayout({this.detached = false, this.hidden = false, this.width, this.height});

  /// Whether the panel has a window of its own.
  final bool detached;

  /// Whether the walk was put away.
  final bool hidden;

  /// The window's width and height, as last made.
  final int? width;

  /// See [width].
  final int? height;

  /// Read from [file]; docked, at the usual size, where there is none or it cannot be read.
  static WalkWindowLayout read(File file) {
    try {
      if (!file.existsSync()) return const WalkWindowLayout();
      final json = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
      int? size(Object? value) => value is num && value >= 200 && value <= 8000 ? value.round() : null;
      return WalkWindowLayout(
          detached: json['detached'] == true,
          hidden: json['hidden'] == true,
          width: size(json['width']),
          height: size(json['height']));
    } on Object {
      return const WalkWindowLayout();
    }
  }

  /// Written to [file]; quiet where it cannot be.
  void write(File file) {
    try {
      file.writeAsStringSync(jsonEncode(<String, Object?>{'detached': detached, 'hidden': hidden, 'width': ?width, 'height': ?height}));
    } on Object {
      // Not kept for the next start.
    }
  }

  /// With what is given changed.
  WalkWindowLayout copyWith({bool? detached, bool? hidden, int? width, int? height}) => WalkWindowLayout(
      detached: detached ?? this.detached,
      hidden: hidden ?? this.hidden,
      width: width ?? this.width,
      height: height ?? this.height);
}

/// Where the window's layout is kept, beside its socket.
File walkWindowLayoutFile(String socket) => File('${File(socket).parent.path}/panel-window.json');

/// The walk's panel in a window of its own, beside the interface and sized as one likes.
///
/// Flutter's own windows are not in the stable release yet, so the window is this program started a
/// second time, as nothing but the panel. The interface keeps everything the walk sees and decides —
/// what is on screen, the ball, the window's image — and the panel only shows and asks. The two
/// talk over a socket in the walk's folder, one JSON object a line: the interface sends what to show,
/// the panel sends what was pressed.
class WalkWindowHost extends ChangeNotifier {
  /// Constructor taking the socket's path and what to do with what the panel sends.
  WalkWindowHost(this.path, {required this.onCommand, this.onClosed, this.start = _startTheWindow});

  /// Where the socket is.
  final String path;

  /// What the panel sent: `{"do": "back" | "next" | "send" | "clear" | "close" | "dock", ...}`.
  final void Function(Map<String, Object?> command) onCommand;

  /// The person closed the window: the walk is put away, and comes back in its window when shown.
  final VoidCallback? onClosed;

  /// How the second window is started; a test starts nothing.
  final Future<void> Function(String path) start;

  ServerSocket? _server;
  Timer? _forgetting;

  /// How long after its window went the panel is noted as back beside the window.
  static Duration forgetAfter = const Duration(seconds: 1);
  Socket? _panel;
  String _shown = '';
  WalkPanelView? _last;

  /// Whether a panel window is there.
  bool get open => _panel != null;

  /// The variable that makes this program the walk's window, naming the socket.
  static const variable = 'GUIDED_WALK_WINDOW';

  /// The variable that gives the window the size it was last made, as `<width>x<height>`; the
  /// plugin's Linux part opens the window at it.
  static const sizeVariable = 'GUIDED_WALK_WINDOW_SIZE';

  static Future<void> _startTheWindow(String path) async {
    final layout = WalkWindowLayout.read(walkWindowLayoutFile(path));
    final environment = Map<String, String>.of(Platform.environment)..[variable] = path;
    // The size it was last made; the plugin's Linux part opens the window at it.
    if (layout.width case final width?) environment[sizeVariable] = '${width}x${layout.height ?? 860}';
    await Process.start(Platform.resolvedExecutable, const <String>[],
        environment: environment, includeParentEnvironment: false, mode: ProcessStartMode.detached);
  }

  File get _layout => walkWindowLayoutFile(path);

  void _keep({required bool detached}) =>
      WalkWindowLayout.read(_layout).copyWith(detached: detached, hidden: false).write(_layout);

  /// Whether the panel had a window of its own when the interface was last left.
  bool get wasDetached => WalkWindowLayout.read(_layout).detached;

  /// Opens the window, listening first so it finds the socket.
  Future<void> detach() async {
    _docking = false;
    _keep(detached: true);
    if (_server == null) {
      final stale = File(path);
      if (stale.existsSync()) stale.deleteSync();
      final server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
      _server = server;
      server.listen(_welcome);
    }
    await start(path);
  }

  void _welcome(Socket panel) {
    _panel?.destroy();
    _panel = panel;
    _shown = '';
    if (_last case final last?) show(last);
    notifyListeners();
    panel.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        try {
          onCommand((jsonDecode(line) as Map).cast<String, Object?>());
        } on FormatException {
          // A line that is not a command is not one.
        }
      },
      onDone: () => _gone(panel),
      onError: (Object _) => _gone(panel),
      cancelOnError: true,
    );
  }

  void _gone(Socket panel) {
    if (_panel != panel) return;
    _panel = null;
    // Closed by the person: the walk is put away, not put back beside the window. Noted a moment later, so the interface going down — which takes its window with
    // it — is not taken for that: it is gone before the moment is up.
    _forgetting?.cancel();
    _forgetting = Timer(forgetAfter, () {
      if (_panel == null && !_docking) onClosed?.call();
    });
    notifyListeners();
  }

  /// Shows [view] in the window, when it differs from what it shows.
  void show(WalkPanelView view) {
    _last = view;
    final line = jsonEncode(view.toJson());
    final panel = _panel;
    if (panel == null || line == _shown) return;
    _shown = line;
    panel.writeln(line);
  }

  /// Closes the window, which puts the panel back beside the interface.
  void dock() {
    _docking = true;
    _panel?.destroy();
    _panel = null;
    _keep(detached: false);
    notifyListeners();
  }

  /// Closes the window and keeps it noted as the walk's place, for when the walk is shown again.
  void close() {
    _docking = true;
    _panel?.destroy();
    _panel = null;
    notifyListeners();
  }

  bool _docking = false;

  @override
  void dispose() {
    _forgetting?.cancel();
    _panel?.destroy();
    unawaited(_server?.close());
    final socket = File(path);
    if (socket.existsSync()) socket.deleteSync();
    super.dispose();
  }
}

/// This program as the walk's window, talking to the app at [path].
class WalkWindowApp extends StatefulWidget {
  /// Constructor taking the socket's path, and the app's look and words.
  const WalkWindowApp(this.path, {this.theme, this.darkTheme, this.texts = const WalkPanelTexts(), super.key});

  /// Where the interface listens.
  final String path;

  /// The app's themes, so its walk looks like it.
  final ThemeData? theme;

  /// See [theme].
  final ThemeData? darkTheme;

  /// The panel's words that an app may say in its own way.
  final WalkPanelTexts texts;

  @override
  State<WalkWindowApp> createState() => _WalkWindowAppState();
}

class _WalkWindowAppState extends State<WalkWindowApp> {
  Socket? _interface;
  WalkPanelView _view = const WalkPanelView();
  String? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final socket = await Socket.connect(InternetAddress(widget.path, type: InternetAddressType.unix), 0);
      _interface = socket;
      socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (!mounted) return;
          setState(() => _view = WalkPanelView.fromJson((jsonDecode(line) as Map).cast<String, Object?>()));
        },
        // The interface closed, or put the panel back: this window has nothing left to show.
        onDone: () => exit(0),
        onError: (Object _) => exit(0),
        cancelOnError: true,
      );
    } on SocketException catch (failed) {
      if (mounted) setState(() => _problem = 'The interface is not there to walk with: ${failed.message}');
    }
  }

  void _do(Map<String, Object?> command) => _interface?.writeln(jsonEncode(command));

  Timer? _keeping;
  Size? _kept;

  /// Keeps the window's size once it has stopped changing.
  void _sized(Size size) {
    if (size == _kept || size.isEmpty) return;
    _keeping?.cancel();
    _keeping = Timer(const Duration(milliseconds: 600), () {
      _kept = size;
      final file = walkWindowLayoutFile(widget.path);
      WalkWindowLayout.read(file).copyWith(width: size.width.round(), height: size.height.round()).write(file);
    });
  }

  @override
  void dispose() {
    _keeping?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Guided walk',
        debugShowCheckedModeBanner: false,
        theme: widget.theme,
        darkTheme: widget.darkTheme,
        home: Scaffold(
          body: Builder(builder: (context) {
            _sized(MediaQuery.sizeOf(context));
            return _body();
          }),
        ),
      );

  Widget _body() => _problem != null
              ? Center(child: Text(_problem!, key: const Key('walk-window-problem')))
              : WalkPanel(
                  view: _view,
                  onBack: () => _do(<String, Object?>{'do': 'back'}),
                  onNext: () => _do(<String, Object?>{'do': 'next'}),
                  onSend: (text, {required withText}) =>
                      _do(<String, Object?>{'do': 'send', 'text': text, 'withText': withText}),
                  onDock: () => _do(<String, Object?>{'do': 'dock'}),
                  onClear: () => _do(<String, Object?>{'do': 'clear'}),
                  onClose: () => _do(<String, Object?>{'do': 'close'}),
                  texts: widget.texts,
                  styleFile: File('${File(widget.path).parent.path}/panel-style.json'),
                );
}

/// The window's name in the walk's folder.
String walkWindowSocket(String folder) => '$folder/window.sock';

/// Whether this process was started as the walk's window; never in a release build.
String? walkWindowPath([Map<String, String>? environment]) {
  if (kReleaseMode) return null;
  final path = (environment ?? Platform.environment)[WalkWindowHost.variable] ?? '';
  return path.isEmpty ? null : path;
}
