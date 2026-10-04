import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the server says when a person starts it in a terminal: what it is, and who starts it.
String handStarted(String folder) {
  final script = Platform.script.toFilePath();
  final repository = File(script).parent.parent.path;
  return '''
This is the guided walk's MCP server for $folder. It waits on its standard input for an agent's
MCP messages and prints nothing until one speaks; an agent starts it, not a person. In Claude Code:

    claude mcp add guided-walk -- dart run $script $folder

and start Claude Code again. The app to walk through is started apart from it, for the example:

    (cd $repository/example && GUIDED_WALK=\$PWD/walk flutter run -d linux)

Ctrl+C ends this server.''';
}

/// The walk's folder offered to an agent as an MCP server over standard input and output.
///
/// It works on the same files an agent without MCP reads and writes, so both ways lead the same walk
/// and the app does not know which one is used. It needs nothing but Dart: no Flutter, no packages,
/// so `dart run` starts it without resolving anything. Started by the agent, it is reached by
/// nobody else; the folder's permissions decide who may read the walk, and nothing authenticates.
class WalkMcpServer {
  /// Constructor taking the walk's folder.
  WalkMcpServer(this.folder) {
    _read = _readBefore() ?? _comments().length;
    _keepRead();
  }

  /// Where the walk's files are.
  final Directory folder;

  /// The protocol versions this server speaks, newest first.
  static const versions = <String>['2025-06-18', '2025-03-26', '2024-11-05'];

  /// How long a look at the window is waited for.
  static Duration lookTimeout = const Duration(seconds: 10);

  /// How often a file is looked at again while waiting.
  static Duration pollEvery = const Duration(milliseconds: 250);

  File _file(String name) => File('${folder.path}/$name');

  /// How many messages were handed to the agent; new ones are those after it. Kept in the folder,
  /// so a server started again goes on where the last one stopped and loses nothing said in
  /// between; only the very first server starts at what is there, which was answered before.
  int _read = 0;

  File get _readFile => _file('agent-read.json');

  int? _readBefore() {
    if (!_readFile.existsSync()) return null;
    return (_decode(_readFile.readAsStringSync())?['messages'] as num?)?.toInt();
  }

  void _keepRead() {
    try {
      folder.createSync(recursive: true);
      final beside = File('${_readFile.path}.part')
        ..writeAsStringSync(jsonEncode(<String, Object?>{'messages': _read}), flush: true);
      beside.renameSync(_readFile.path);
    } on FileSystemException {
      // Kept for this server only.
    }
  }

  List<Map<String, Object?>> _comments() {
    final file = _file('comments.jsonl');
    if (!file.existsSync()) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty) ?_decode(line),
    ];
  }

  static Map<String, Object?>? _decode(String text) {
    try {
      return (jsonDecode(text) as Map).cast<String, Object?>();
    } on Object {
      return null;
    }
  }

  /// Serves JSON-RPC lines read from [input] and writes the answers to [output], one a line, until
  /// the input ends.
  Future<void> serve(Stream<String> input, StringSink output) async {
    final pending = <Future<void>>[];
    await for (final line in input) {
      if (line.trim().isEmpty) continue;
      // Each request is answered when it is done: waiting for a message must not hold up the rest.
      pending.add(_handle(line).then((answer) {
        if (answer != null) output.writeln(jsonEncode(answer));
      }));
    }
    await Future.wait(pending);
    if (output is IOSink) await output.flush();
  }

  Future<Map<String, Object?>?> _handle(String line) async {
    final request = _decode(line);
    if (request == null) {
      return _error(null, -32700, 'Not JSON');
    }
    final id = request['id'];
    final method = request['method'];
    // A notification has no id and is answered by nobody.
    if (id == null) return null;
    final params = (request['params'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    try {
      return switch (method) {
        'initialize' => _result(id, _initialize(params)),
        'ping' => _result(id, const <String, Object?>{}),
        'tools/list' => _result(id, <String, Object?>{'tools': _tools}),
        'tools/call' => _result(id, await _call(params)),
        _ => _error(id, -32601, 'No method $method'),
      };
    } on Object catch (failed) {
      return _error(id, -32603, '$failed');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final asked = params['protocolVersion'];
    return <String, Object?>{
      'protocolVersion': versions.contains(asked) ? asked : versions.first,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{'listChanged': false},
      },
      'serverInfo': <String, Object?>{'name': 'guided-walk', 'version': '0.2.0'},
      'instructions': 'Leads a person through a Flutter app beside its window. Write the walk with '
          'walk_set, wait for what the person says with walk_wait, answer with walk_say, and look at '
          'the window with walk_look. walk_status says which step is shown, and whether the person has put '
          'the walk away; then nothing is seen until they show it again.',
    };
  }

  static Map<String, Object?> _result(Object id, Map<String, Object?> result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, Object?> _error(Object? id, int code, String message) => <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      };

  static const _step = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'say': <String, Object?>{'type': 'string', 'description': 'What the step tells the person.'},
      'at': <String, Object?>{
        'description': 'What it points at: a key, or a list whose first on screen counts.',
        'anyOf': <Object?>[
          <String, Object?>{'type': 'string'},
          <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
        ],
      },
      'then': <String, Object?>{'type': 'string', 'description': 'What moves the walk on when it appears.'},
    },
    'required': <String>['say'],
  };

  static const _tools = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'walk_status',
      'description': 'Which walk is shown, which step, whether it is put away, and whether the '
          'person waits for an answer.',
      'inputSchema': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
    },
    <String, Object?>{
      'name': 'walk_set',
      'description': 'Writes the walk the app shows. It keeps its place unless from is given.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string'},
          'steps': <String, Object?>{'type': 'array', 'items': _step},
          'from': <String, Object?>{'type': 'integer', 'description': 'The step to show, from 0.'},
        },
        'required': <String>['title', 'steps'],
      },
    },
    <String, Object?>{
      'name': 'walk_say',
      'description': 'Answers the person in the panel beside the window.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'text': <String, Object?>{'type': 'string'},
        },
        'required': <String>['text'],
      },
    },
    <String, Object?>{
      'name': 'walk_wait',
      'description': 'Waits until the person says something, or the walk sends the window by '
          'itself, and returns it with the window\'s state and image. Returns at once with what '
          'is unread.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'timeout_seconds': <String, Object?>{'type': 'integer', 'description': 'At most 600; 60 by default.'},
        },
      },
    },
    <String, Object?>{
      'name': 'walk_look',
      'description': 'Looks at the window now: its state as text and its image, secrets blanked.',
      'inputSchema': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
    },
  ];

  /// Said beside every tool's answer while the person has put the walk away: the panel is not on
  /// screen, so nothing the agent writes or says is seen until it is shown again.
  static const putAway = 'The person has put the walk away: the panel is not on screen, and nothing '
      'written or said is seen until it is shown again. Ask them to press "Show the guided walk", the '
      'signpost at the right of the app\'s top bar.';

  /// Said beside every tool's answer while the app that showed the walk no longer runs.
  static const notRunning = 'The app is not running: it was closed, or ended. Nothing is shown or '
      'said until it is started again with this walk\'s folder.';

  /// Whether the app that last wrote `status.json` still runs: its process is there, and on Linux it
  /// is still that program, not another one given the same number since.
  bool get _appRunning {
    final file = _file('status.json');
    if (!file.existsSync()) return false;
    final status = _decode(file.readAsStringSync());
    final pid = (status?['pid'] as num?)?.toInt();
    if (pid == null) return true;
    final proc = Directory('/proc/$pid');
    if (Directory('/proc').existsSync()) {
      if (!proc.existsSync()) return false;
      final program = status?['program'];
      if (program is! String) return true;
      try {
        return Link('${proc.path}/exe').resolveSymbolicLinksSync() == File(program).resolveSymbolicLinksSync();
      } on FileSystemException {
        return true;
      }
    }
    return Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0;
  }

  bool get _hidden {
    final file = _file('status.json');
    if (!file.existsSync()) return false;
    return _decode(file.readAsStringSync())?['hidden'] == true;
  }

  Future<Map<String, Object?>> _call(Map<String, Object?> params) async {
    final result = await _tool(params);
    final note = !_appRunning ? notRunning : (_hidden ? putAway : null);
    if (note == null) return result;
    return <String, Object?>{
      ...result,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': note},
        ...(result['content']! as List<Object?>),
      ],
    };
  }

  Future<Map<String, Object?>> _tool(Map<String, Object?> params) async {
    final arguments = (params['arguments'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return switch (params['name']) {
      'walk_status' => _text(_status()),
      'walk_set' => await _set(arguments),
      'walk_say' => await _say(arguments),
      'walk_wait' => await _wait(arguments),
      'walk_look' => await _lookNow(),
      final other => _failed('No tool $other'),
    };
  }

  static Map<String, Object?> _text(String text) => <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
      };

  static Map<String, Object?> _failed(String text) => <String, Object?>{..._text(text), 'isError': true};

  String _status() {
    final file = _file('status.json');
    if (!file.existsSync()) return 'The app has not started this walk: no status.json in ${folder.path}.';
    return file.readAsStringSync();
  }

  Future<Map<String, Object?>> _set(Map<String, Object?> arguments) async {
    final steps = arguments['steps'];
    if (steps is! List || steps.any((each) => each is! Map || each['say'] is! String)) {
      return _failed('Every step needs what it says, in "say".');
    }
    folder.createSync(recursive: true);
    final walk = <String, Object?>{
      'title': arguments['title'] ?? '',
      'steps': steps,
      if (arguments['from'] case final int from) 'from': from,
    };
    final beside = File('${_file('walk.json').path}.part');
    await beside.writeAsString(const JsonEncoder.withIndent('  ').convert(walk), flush: true);
    await beside.rename(_file('walk.json').path);
    return _text('The walk "${walk['title']}" is written, ${steps.length} steps.');
  }

  Future<Map<String, Object?>> _say(Map<String, Object?> arguments) async {
    final text = arguments['text'];
    if (text is! String || text.trim().isEmpty) return _failed('Nothing to say.');
    folder.createSync(recursive: true);
    await _file('answers.jsonl')
        .writeAsString('${jsonEncode(<String, Object?>{'text': text})}\n', mode: FileMode.append, flush: true);
    return _text('Said.');
  }

  Future<Map<String, Object?>> _wait(Map<String, Object?> arguments) async {
    final seconds = (arguments['timeout_seconds'] as num?)?.toInt().clamp(0, 600) ?? 60;
    final until = DateTime.now().add(Duration(seconds: seconds));
    while (true) {
      final comments = _comments();
      if (comments.length > _read) {
        final fresh = comments.sublist(_read);
        _read = comments.length;
        _keepRead();
        return _messages(fresh);
      }
      if (!DateTime.now().isBefore(until)) return _text('Nothing was said in $seconds seconds.');
      // Waiting for an app that is gone would wait out the whole time for nothing.
      if (!_appRunning) return _text('Nothing more will be said: the app is not running.');
      await Future<void>.delayed(pollEvery);
    }
  }

  /// The messages as text, each with the window's state; the image of the last one beside them.
  Map<String, Object?> _messages(List<Map<String, Object?>> fresh) {
    final content = <Object?>[];
    for (final each in fresh) {
      final who = each['byTheWalk'] == true ? 'The walk sent the window by itself' : 'The person said';
      final said = '${each['text'] ?? ''}';
      content.add(<String, Object?>{
        'type': 'text',
        'text': '$who${said.isEmpty ? ' nothing, and sent the window' : ': $said'}\n'
            'At step ${each['step']}: ${each['stepSays']}\n\n${each['state']}',
      });
    }
    if (_image(fresh.last['image']) case final image?) content.add(image);
    return <String, Object?>{'content': content};
  }

  Map<String, Object?>? _image(Object? name) {
    if (name is! String) return null;
    final file = _file(name);
    if (!file.existsSync()) return null;
    return <String, Object?>{'type': 'image', 'data': base64Encode(file.readAsBytesSync()), 'mimeType': 'image/png'};
  }

  Future<Map<String, Object?>> _lookNow() async {
    final answered = _file('look.json');
    final before = answered.existsSync() ? (_decode(answered.readAsStringSync())?['n'] as num?)?.toInt() ?? 0 : 0;
    final asked = before + 1;
    folder.createSync(recursive: true);
    await _file('look-request.json').writeAsString(jsonEncode(<String, Object?>{'n': asked}), flush: true);
    final until = DateTime.now().add(lookTimeout);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(pollEvery);
      if (!answered.existsSync()) continue;
      final look = _decode(answered.readAsStringSync());
      if (look == null || look['n'] != asked) continue;
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'At step ${look['step']}: ${look['stepSays']}\n\n${look['state']}'},
          ?_image(look['image']),
        ],
      };
    }
    return _failed('The app did not show its window within ${lookTimeout.inSeconds} seconds: is it '
        'running with this walk\'s folder?');
  }
}
