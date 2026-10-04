import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One step of a guided walk: what to say, the key of what it points at, and the key whose
/// appearance means the step was done.
class WalkStep {
  /// Constructor taking what the walk file says.
  const WalkStep({required this.say, this.at = const <String>[], this.then = ''});

  /// Reads one from the walk file; `at` is one key, or a list of them of which the first on screen
  /// is pointed at.
  factory WalkStep.from(Map<String, dynamic> map) => WalkStep(
        say: '${map['say'] ?? ''}',
        at: switch (map['at']) {
          final List<dynamic> keys => <String>[for (final each in keys) '$each'],
          null || '' => const <String>[],
          final key => <String>['$key'],
        },
        then: '${map['then'] ?? ''}',
      );

  /// The instruction, in a sentence or two.
  final String say;

  /// The keys of the element the bubble points at, the first on screen; empty for a step that points
  /// at nothing. More than one where a key depends on where the person is.
  final List<String> at;

  /// The key whose appearance moves the walk on; empty when only "Next" does.
  final String then;
}

/// One line of the conversation beside the walk.
class WalkMessage {
  /// Constructor taking who said it and what.
  const WalkMessage({required this.fromThePerson, required this.text, this.fromTheWalk = false});

  /// Whether the person wrote it, rather than the agent leading the walk.
  final bool fromThePerson;

  /// Whether the walk itself said it — that it lost its way — which is neither the person's nor the
  /// agent's, and is drawn as its own.
  final bool fromTheWalk;

  /// What was said.
  final String text;
}

/// A guided walk through the interface, with the agent leading it beside it.
///
/// **Development builds only**, and only when started with a folder: everything goes through that
/// folder on this computer and nowhere else. The leading agent writes `walk.json` (the steps) and
/// appends to `answers.jsonl`; the interface appends to `comments.jsonl`, with an image of its own
/// window beside each comment.
class WalkSession extends ChangeNotifier {
  /// Constructor taking the folder the walk goes through.
  WalkSession(this.folder);

  /// The walk whose folder [variable] names, or null when there is none: no walk unless asked for,
  /// and never in a release build.
  static WalkSession? fromEnvironment({String variable = 'GUIDED_WALK', Map<String, String>? environment}) {
    if (kReleaseMode) return null;
    final folder = (environment ?? Platform.environment)[variable] ?? '';
    return folder.isEmpty ? null : WalkSession(Directory(folder));
  }

  /// Where the walk file, the comments, the images and the answers are.
  final Directory folder;

  /// The steps, as the walk file last said them.
  List<WalkStep> steps = const <WalkStep>[];

  /// The step shown now; equal to the number of steps once the walk is through.
  int index = 0;

  /// The walk's title, from its file.
  String title = '';

  /// What was said beside the walk, oldest first.
  final List<WalkMessage> messages = <WalkMessage>[];

  /// Whether the person said something the agent has not answered yet.
  bool get waitingForAnAnswer => messages.isNotEmpty && (messages.last.fromThePerson || messages.last.fromTheWalk);

  /// Whether the walk is put away: no panel, nothing pointed at, nothing sent by itself, until it is
  /// shown again from the window's top bar.
  bool hidden = false;

  /// Starts put away or not, as it was left, without telling anyone: nothing has changed yet. What
  /// it shows is written again, so an agent reads the same.
  void startHidden(bool put) {
    hidden = put;
    if (folder.existsSync()) _writeStatus();
  }

  /// Puts the walk away.
  void hide() {
    if (hidden) return;
    hidden = true;
    notifyListeners();
  }

  /// Shows the walk again, where it was.
  void show() {
    if (!hidden) return;
    hidden = false;
    notifyListeners();
  }

  /// The step shown now, or null once the walk is through.
  WalkStep? get current => index < steps.length ? steps[index] : null;

  Timer? _polling;
  DateTime? _walkRead;
  int _answersRead = 0;
  int _missing = 0;
  int _lost = 0;

  /// When the walk last moved by itself, and which way: it does not turn back within a few seconds,
  /// so two rules that each think the other step is right cannot flip it back and forth.
  DateTime? _movedAt;
  int _movedBy = 0;
  /// How long it does not turn back; a test that turns it at once sets it to nothing.
  static Duration settle = const Duration(seconds: 4);

  bool _mayMove(int by) {
    final at = _movedAt;
    return at == null || by == _movedBy || DateTime.now().difference(at) >= settle;
  }

  void _moved(int by) {
    _movedAt = DateTime.now();
    _movedBy = by;
  }

  /// Called once when the walk has lost its way: no step's element is on screen for a while. The
  /// frame sends the window to the agent then, which decides how to go on.
  void Function()? onLost;
  int _comments = 0;

  File get _walkFile => File('${folder.path}/walk.json');
  File get _answers => File('${folder.path}/answers.jsonl');
  File get _commentsFile => File('${folder.path}/comments.jsonl');

  /// What was said beside the walk, in order, by everyone: read back when the interface starts
  /// again, which before kept only the agent's answers.
  File get _conversation => File('${folder.path}/conversation.jsonl');

  void _remember(WalkMessage message) {
    messages.add(message);
    try {
      _conversation.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
          'fromThePerson': message.fromThePerson,
          'fromTheWalk': message.fromTheWalk,
          'text': message.text,
          'answersRead': _answersRead,
        })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Shown, though not kept for the next start.
    }
  }

  /// Forgets what was said beside the walk, here and in its folder; an answer already read is not
  /// read again.
  void clearConversation() {
    messages.clear();
    try {
      _conversation.writeAsStringSync('${jsonEncode(<String, Object?>{'answersRead': _answersRead})}\n', flush: true);
    } on FileSystemException {
      // Cleared here, though not in the folder.
    }
    notifyListeners();
  }

  /// The conversation as it was kept, and how far the answers were read then.
  void _recall() {
    if (!_conversation.existsSync()) return;
    for (final line in _conversation.readAsLinesSync()) {
      try {
        final each = (jsonDecode(line) as Map).cast<String, Object?>();
        final read = each['answersRead'];
        if (read is int && read > _answersRead) _answersRead = read;
        // Where it was cleared: how far the answers were read, and nothing said.
        if (!each.containsKey('text')) continue;
        messages.add(WalkMessage(
          fromThePerson: each['fromThePerson'] == true,
          fromTheWalk: each['fromTheWalk'] == true,
          text: each['text'] as String? ?? '',
        ));
      } on Object {
        // A line half written when the interface stopped.
      }
    }
  }

  /// Reads the walk and the answers, and keeps reading them while it runs.
  void start({Duration every = const Duration(milliseconds: 700)}) {
    folder.createSync(recursive: true);
    if (_polling == null && messages.isEmpty) _recall();
    read();
    _writeStatus();
    _polling ??= Timer.periodic(every, (_) => read());
  }

  /// How the window is looked at, given by the frame: its state as text and its image, secrets
  /// blanked. Asked for by an agent through `look-request.json`, answered in `look.json`.
  Future<({String state, Uint8List? image})> Function()? onLook;

  int _looked = 0;
  bool _looking = false;

  File get _lookRequest => File('${folder.path}/look-request.json');
  File get _look => File('${folder.path}/look.json');
  File get _status => File('${folder.path}/status.json');
  String _statusWritten = '';

  /// Answers a request to look at the window: `{"n": <number>}`, answered once per number.
  Future<void> _answerLook() async {
    final look = onLook;
    if (look == null || _looking || !_lookRequest.existsSync()) return;
    int? asked;
    try {
      asked = ((jsonDecode(_lookRequest.readAsStringSync()) as Map)['n'] as num?)?.toInt();
    } on Object {
      return;
    }
    if (asked == null || asked <= _looked) return;
    _looking = true;
    try {
      final seen = await look();
      final at = DateTime.now().toUtc();
      String? imageName;
      if (seen.image case final image?) {
        imageName = 'look-${at.millisecondsSinceEpoch}.png';
        await File('${folder.path}/$imageName').writeAsBytes(image, flush: true);
      }
      await _writeWhole(_look, <String, Object?>{
        'n': asked,
        'at': at.toIso8601String(),
        'step': index,
        'stepSays': current?.say ?? '',
        'state': seen.state,
        'image': ?imageName,
      });
      _looked = asked;
    } finally {
      _looking = false;
    }
  }

  /// Written to a file beside it and moved over it, so a reader never sees half of it.
  static Future<void> _writeWhole(File file, Map<String, Object?> json) async {
    final beside = File('${file.path}.part');
    await beside.writeAsString(jsonEncode(json), flush: true);
    await beside.rename(file.path);
  }

  /// What the walk shows now, for an agent to read: which walk, which step, and whether it is put
  /// away or waits for an answer. Written whenever it changes.
  void _writeStatus() {
    final step = current;
    final status = jsonEncode(<String, Object?>{
      // Which process shows the walk, so an agent can tell whether it still runs: an app that is
      // closed, or ends without a word, writes nothing more.
      'pid': pid,
      'program': Platform.resolvedExecutable,
      'title': title,
      'steps': steps.length,
      'step': index,
      'says': step?.say,
      'at': step?.at,
      'then': step?.then,
      'through': steps.isNotEmpty && step == null,
      'hidden': hidden,
      'waitingForAnAnswer': waitingForAnAnswer,
      'messages': messages.length,
    });
    if (status == _statusWritten) return;
    _statusWritten = status;
    try {
      final beside = File('${_status.path}.part')..writeAsStringSync(status, flush: true);
      beside.renameSync(_status.path);
    } on FileSystemException {
      // Read again on the next change.
      _statusWritten = '';
    }
  }

  @override
  void notifyListeners() {
    if (folder.existsSync()) _writeStatus();
    super.notifyListeners();
  }

  /// Reads what changed in the walk file and the answers since last time.
  void read() {
    unawaited(_answerLook());
    var changed = false;
    if (_walkFile.existsSync()) {
      final modified = _walkFile.lastModifiedSync();
      if (_walkRead == null || modified.isAfter(_walkRead!)) {
        _walkRead = modified;
        try {
          final walk = jsonDecode(_walkFile.readAsStringSync()) as Map<String, dynamic>;
          title = '${walk['title'] ?? ''}';
          steps = <WalkStep>[
            for (final each in (walk['steps'] as List<dynamic>? ?? const <dynamic>[]))
              if (each is Map<String, dynamic>) WalkStep.from(each),
          ];
          // A walk rewritten under way keeps its place, as far as it still goes.
          if (index > steps.length) index = steps.length;
          if (walk['from'] is int) index = (walk['from'] as int).clamp(0, steps.length);
        } on FormatException {
          // Half written: read again on the next round.
          _walkRead = null;
        }
        changed = true;
      }
    }
    if (_answers.existsSync()) {
      final lines = _answers.readAsLinesSync();
      final fresh = lines.skip(_answersRead).toList();
      _answersRead = lines.length;
      for (final line in fresh) {
        if (line.trim().isEmpty) continue;
        try {
          final answer = jsonDecode(line) as Map<String, dynamic>;
          _remember(WalkMessage(fromThePerson: false, text: '${answer['text'] ?? ''}'));
        } on FormatException {
          _remember(WalkMessage(fromThePerson: false, text: line));
        }
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// How many looks in a row with nothing of the walk on screen make it lost.
  static const lostAfter = 8;

  /// Moves on to the next step.
  void next() {
    if (index >= steps.length) return;
    index++;
    notifyListeners();
  }

  /// Moves back one step.
  void back() {
    if (index == 0) return;
    index--;
    notifyListeners();
  }

  /// Moves on when what the step waits for is on screen.
  ///
  /// A step that names nothing to wait for moves on when the next step's element appears: clicking
  /// what it points at is what usually brings the next one.
  ///
  /// **And back**: a step whose element went away while the previous
  /// step's is there again — a dialog cancelled — goes back to that one, after two looks in a row,
  /// so a frame between two screens does not move it.
  void seen(bool Function(String key) onScreen, {bool working = false}) {
    final step = current;
    if (step == null) return;
    if (working) _lost = 0;
    // No jumping ahead to a later step whose element happens to be on screen: in a form, a later
    // step's "Close" is there from the start, and the walk sent the person to it before the form was
    // filled. A person faster than the walk says so, or presses Next.
    final before = index > 0 ? steps[index - 1] : null;
    // Lost: the step's element is not there, nor the one before it, nor any later one. The person
    // went somewhere the walk did not expect; the agent leading it is asked once.
    if (step.at.isNotEmpty &&
        !step.at.any(onScreen) &&
        !(before?.at.any(onScreen) ?? false)) {
      if (!working && ++_lost == lostAfter) onLost?.call();
    } else {
      _lost = 0;
    }
    // What the step waits for comes first: a step waiting for its dialog to close sees its own
    // element go and the one before come back at the same time, and going back then undid it.
    if (step.then.isNotEmpty) {
      // `!key` waits for something to go: a dialog closed, a question answered.
      final gone = step.then.startsWith('!');
      if (onScreen(gone ? 'usable:${step.then.substring(1)}' : step.then) != gone && _mayMove(1)) {
        _missing = 0;
        next();
        _moved(1);
        return;
      }
    }
    if (step.at.isNotEmpty &&
        !step.at.any(onScreen) &&
        before != null &&
        before.at.isNotEmpty &&
        before.at.any(onScreen)) {
      if (++_missing >= 2 && _mayMove(-1)) {
        _missing = 0;
        back();
        _moved(-1);
      }
      return;
    }
    _missing = 0;
    if (step.then.isNotEmpty) return;
    // Only once its own element has gone: the next one is often there from the start, and moving on
    // while this one still waited made the walk flip between two steps.
    final following = index + 1 < steps.length ? steps[index + 1] : null;
    if (following != null &&
        following.at.isNotEmpty &&
        following.at.any(onScreen) &&
        (step.at.isEmpty || !step.at.any(onScreen)) &&
        _mayMove(1)) {
      next();
      _moved(1);
    }
  }

  /// Writes what the person said, with the window's state and, where it could be taken, an image of
  /// the window; returns the name the image was written under, or null.
  Future<String?> comment(String text, {required String state, Uint8List? image, bool byTheWalk = false}) async {
    folder.createSync(recursive: true);
    _comments++;
    final at = DateTime.now().toUtc();
    String? imageName;
    if (image != null) {
      imageName = 'window-${at.millisecondsSinceEpoch}-$_comments.png';
      await File('${folder.path}/$imageName').writeAsBytes(image, flush: true);
    }
    await _commentsFile.writeAsString(
      '${jsonEncode(<String, Object?>{
        'at': at.toIso8601String(),
        'text': text,
        'byTheWalk': byTheWalk,
        'step': index,
        'stepSays': current?.say ?? '',
        'state': state,
        'image': ?imageName,
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
    // The window sent alone waits for an answer too: it was sent to be looked at.
    _remember(WalkMessage(
        fromThePerson: !byTheWalk, fromTheWalk: byTheWalk, text: text.isEmpty ? '(the window)' : text));
    notifyListeners();
    return imageName;
  }

  @override
  void dispose() {
    _polling?.cancel();
    super.dispose();
  }
}
