import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guided_walk/guided_walk.dart';

/// A guided walk beside the window: steps pointed at by key, moved on by what appears, and
/// what the person says written down with the window's state, secrets left out.
void main() {
  late Directory folder;
  late WalkSession walk;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('walk-');
    walk = WalkSession(folder);
  });

  tearDown(() {
    walk.dispose();
    folder.deleteSync(recursive: true);
  });

  void walkFile(List<Map<String, String>> steps) => File('${folder.path}/walk.json')
      .writeAsStringSync(jsonEncode(<String, Object>{'title': 'A first start', 'steps': steps}));

  /// A window with a button that opens a dialog, a field, a hidden field and a terminal stand-in.
  Widget window() => MaterialApp(
        builder: (context, child) => WalkFrame(walk: walk, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: <Widget>[
                FilledButton(
                  key: const Key('start-work'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      key: Key('default-dialog'),
                      title: Text('Start work without a project'),
                    ),
                  ),
                  child: const Text('Start work'),
                ),
                const TextButton(key: Key('not-yet'), onPressed: null, child: Text('Not yet')),
                TextField(
                  key: const Key('default-address'),
                  controller: TextEditingController(text: '/home/me/my-first.git'),
                  decoration: const InputDecoration(labelText: 'Its address'),
                ),
                TextField(
                  key: const Key('passphrase'),
                  obscureText: true,
                  controller: TextEditingController(text: 'not-for-anybody'),
                  decoration: const InputDecoration(labelText: 'Passphrase'),
                ),
                const SizedBox(height: 40, child: WalkSecret(child: Text('code: 4711-secret'))),
              ],
            ),
          ),
        ),
      );

  /// Lets the walk look again, as it does on its own every few hundred milliseconds.
  Future<void> look(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  test('the conversation is there again, in order, when the interface starts again', () async {
    final first = WalkSession(folder)..read();
    await first.comment('Why is it grey?', state: '');
    File('${folder.path}/answers.jsonl').writeAsStringSync('${jsonEncode(<String, String>{'text': 'It waits.'})}\n',
        mode: FileMode.append);
    first.read();
    await first.comment('', state: '', byTheWalk: true);

    final again = WalkSession(folder)..start(every: const Duration(hours: 1));
    expect(<String>[for (final each in again.messages) each.text], <String>['Why is it grey?', 'It waits.', '(the window)']);
    expect(again.messages.first.fromThePerson, isTrue);
    expect(again.messages.last.fromTheWalk, isTrue);
    // An answer read before is not read again.
    again.read();
    expect(again.messages, hasLength(3));
    again.dispose();
  });

  test('a cleared conversation stays cleared, and its answers are not read again', () async {
    final first = WalkSession(folder)..read();
    await first.comment('Hello', state: '');
    File('${folder.path}/answers.jsonl').writeAsStringSync('${jsonEncode(<String, String>{'text': 'Hi.'})}\n',
        mode: FileMode.append);
    first
      ..read()
      ..clearConversation();
    expect(first.messages, isEmpty);

    final again = WalkSession(folder)..start(every: const Duration(hours: 1));
    expect(again.messages, isEmpty);
    File('${folder.path}/answers.jsonl').writeAsStringSync('${jsonEncode(<String, String>{'text': 'New.'})}\n',
        mode: FileMode.append);
    again.read();
    expect(<String>[for (final each in again.messages) each.text], <String>['New.']);
    again.dispose();
  });

  testWidgets('a walk put away shows nothing, is kept put away, and comes back where it was', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Click it.', 'at': 'start-work'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await look(tester);
    expect(find.byKey(const Key('walk-panel')), findsOneWidget);
    expect(find.byKey(const Key('walk-ball')), findsOneWidget);

    await tester.tap(find.byKey(const Key('walk-close')));
    await tester.pump();
    await look(tester);
    expect(walk.hidden, isTrue);
    expect(find.byKey(const Key('walk-panel')), findsNothing);
    expect(find.byKey(const Key('walk-ball')), findsNothing, reason: 'nothing pointed at');
    final layout = File('${folder.path}/panel-window.json');
    expect(jsonDecode(layout.readAsStringSync()), containsPair('hidden', true));

    walk.show();
    await tester.pump();
    await look(tester);
    expect(find.byKey(const Key('walk-panel')), findsOneWidget);
    expect(jsonDecode(layout.readAsStringSync()), containsPair('hidden', false));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('what the walk shows is written for an agent, and changes with it', () async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'One.', 'at': 'one'},
      <String, String>{'say': 'Two.', 'at': 'two'},
    ]);
    walk.start(every: const Duration(hours: 1));
    Map<String, Object?> status() =>
        (jsonDecode(File('${folder.path}/status.json').readAsStringSync()) as Map).cast<String, Object?>();
    expect(status(), allOf(containsPair('steps', 2), containsPair('step', 0), containsPair('says', 'One.')));
    walk.next();
    expect(status(), containsPair('says', 'Two.'));
    walk.hide();
    expect(status(), containsPair('hidden', true));
  });

  test('a request to look at the window is answered once, with its state and image', () async {
    var looked = 0;
    walk.onLook = () async {
      looked++;
      return (state: 'Buttons: Go', image: Uint8List.fromList(<int>[7]));
    };
    File('${folder.path}/look-request.json').writeAsStringSync('{"n": 1}');
    walk.read();
    final look = File('${folder.path}/look.json');
    while (!look.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final answer = jsonDecode(look.readAsStringSync()) as Map;
    expect(answer['n'], 1);
    expect(answer['state'], 'Buttons: Go');
    expect(File('${folder.path}/${answer['image']}').readAsBytesSync(), <int>[7]);
    walk.read();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(looked, 1, reason: 'one request, one look');
  });

  testWidgets('a walk left put away starts put away, and says so to an agent', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Click it.', 'at': 'start-work'},
    ]);
    File('${folder.path}/panel-window.json').writeAsStringSync('{"detached": false, "hidden": true}');
    walk.read();
    await tester.pumpWidget(window());
    await tester.pump();
    expect(find.byKey(const Key('walk-panel')), findsNothing);
    expect(jsonDecode(File('${folder.path}/status.json').readAsStringSync()), containsPair('hidden', true));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a step waiting for its dialog to close goes on when it closes, not back', () {
    File('${folder.path}/walk.json').writeAsStringSync(jsonEncode(<String, Object>{
      'title': 'A greeting',
      'steps': <Object>[
        <String, String>{'say': 'Press Greet me.', 'at': 'greet', 'then': 'greeting'},
        <String, String>{'say': 'Close the greeting.', 'at': 'greeting-close', 'then': '!greeting'},
        <String, String>{'say': 'That is all.'},
      ],
    }));
    walk.read();
    // The dialog is open: the step before it is done.
    walk.seen((key) => key == 'greeting' || key == 'usable:greeting' || key == 'greeting-close');
    expect(walk.index, 1);
    // Closed: its own element went, and the one before is back, at the same moment.
    for (var look = 0; look < 3; look++) {
      walk.seen((key) => key == 'greet' || key == 'usable:greet');
    }
    expect(walk.index, 2);
  });

  testWidgets('a field given no controller is read as typed, and a hidden one is not read', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextField(key: Key('name'), decoration: InputDecoration(labelText: 'Your name')),
            TextField(key: Key('secret'), obscureText: true, decoration: InputDecoration(labelText: 'Password')),
          ],
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('name')), 'Michael');
    await tester.enterText(find.byKey(const Key('secret')), 'hunter2');
    await tester.pump();
    final root = tester.element(find.byType(Scaffold));
    final state = windowState(root);
    expect(state, contains('Your name [name]: "Michael"'));
    expect(state, contains('Password [secret]: (typed, hidden)'));
    expect(state, isNot(contains('hunter2')));
    expect(walkSees(root, 'filled:name'), isTrue);
  });

  testWidgets('without GUIDED_WALK there is no walk', (tester) async {
    expect(WalkSession.fromEnvironment(environment: const <String, String>{}), isNull);
    expect(WalkSession.fromEnvironment(environment: const <String, String>{'GUIDED_WALK': '/tmp/a-walk'})?.folder.path,
        '/tmp/a-walk');
    // An app names its own variable.
    expect(
        WalkSession.fromEnvironment(variable: 'MY_APP_WALK', environment: const <String, String>{'MY_APP_WALK': '/w'})
            ?.folder
            .path,
        '/w');
  });

  testWidgets('a step points at its element, and moves on when what it waits for appears', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Click here: a dialog opens.', 'at': 'start-work', 'then': 'default-dialog'},
      <String, String>{'say': 'Type its address.', 'at': 'default-address'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await look(tester);

    expect(find.textContaining('Click here: a dialog opens.'), findsOneWidget);
    expect(find.byKey(const Key('walk-ball')), findsOneWidget);
    final framed = tester.getRect(find.byKey(const Key('walk-target')));
    expect(framed.contains(tester.getCenter(find.byKey(const Key('start-work')))), isTrue);

    // The ball never takes a click from what it is drawn on, and no sentence is drawn over the window.
    expect(find.byKey(const Key('walk-ball')).hitTestable(), findsNothing);
    expect(find.byKey(const Key('walk-bubble')), findsNothing);
    await tester.tap(find.byKey(const Key('start-work')));
    // The ball pulses for as long as it points, so nothing here ever settles: time is let pass.
    await tester.pump(const Duration(milliseconds: 500));
    await look(tester);
    expect(walk.index, 1);
    expect(find.textContaining('Step 2 of 2: Type its address.'), findsOneWidget);
    // The step done stays readable.
    expect(find.textContaining('✓ 1. Click here: a dialog opens.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('walk-next')));
    await tester.pump();
    expect(find.text('The walk is through.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("a step with nothing to wait for moves on when the next step's element appears", (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Click here.', 'at': 'start-work'},
      <String, String>{'say': 'This dialog.', 'at': 'default-dialog'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await look(tester);
    expect(walk.index, 0);

    await tester.tap(find.byKey(const Key('start-work')));
    await tester.pump(const Duration(milliseconds: 500));
    await look(tester);
    expect(walk.index, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a step whose element is not on screen says so rather than pointing anywhere', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Press Sign in first.', 'at': 'start-sign-in-first'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await look(tester);

    expect(find.byKey(const Key('walk-target')), findsNothing);
    expect(find.textContaining('What it points at is not on screen.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a step whose element went away goes back to the one before', (tester) async {
    WalkSession.settle = Duration.zero;
    addTearDown(() => WalkSession.settle = const Duration(seconds: 4));
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Open the dialog.', 'at': 'start-work', 'then': 'default-dialog'},
      <String, String>{'say': 'Something in the dialog.', 'at': 'default-dialog'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await tester.tap(find.byKey(const Key('start-work')));
    await tester.pump(const Duration(milliseconds: 500));
    await look(tester);
    expect(walk.index, 1);

    // Cancelled: the dialog is gone, and what the step before points at is there.
    Navigator.of(tester.element(find.byKey(const Key('default-dialog')))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('default-dialog')), findsNothing, reason: 'the dialog is gone');
    await look(tester);
    await look(tester);
    expect(walk.index, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a later step whose element is on screen does not pull the walk ahead', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Something not here.', 'at': 'start-sign-in-first'},
      <String, String>{'say': 'Not here either.', 'at': 'start-go'},
      <String, String>{'say': 'The address.', 'at': 'default-address'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await look(tester);
    expect(walk.index, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('what an open dialog covers is not pointed at', (tester) async {
    await tester.pumpWidget(window());
    await tester.tap(find.byKey(const Key('start-work')));
    await tester.pump(const Duration(milliseconds: 500));
    final root = tester.element(find.byType(Scaffold));
    expect(elementKeyed(tester.element(find.byType(WalkFrame)), 'start-work'), isNull);
    expect(elementKeyed(root, 'default-dialog'), isNull, reason: 'the dialog is not under the page');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a walk that lost its way says so, once', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Somewhere else.', 'at': 'nowhere-at-all'},
    ]);
    walk.read();
    var lost = 0;
    walk.onLost = () => lost++;
    for (var each = 0; each < WalkSession.lostAfter + 3; each++) {
      walk.seen((_) => false);
    }
    expect(lost, 1);
  });

  testWidgets('a step on a form waits for its field to be filled', (tester) async {
    await tester.pumpWidget(window());
    final root = tester.element(find.byType(Scaffold));
    expect(walkSees(root, 'filled:default-address'), isTrue);
    await tester.enterText(find.byKey(const Key('default-address')), '');
    await tester.pump();
    expect(walkSees(root, 'filled:default-address'), isFalse);
    expect(walkSees(root, 'default-address'), isTrue);
    expect(walkSees(root, 'usable:not-yet'), isFalse, reason: 'a button that cannot be pressed is done with');
    expect(walkSees(root, 'not-yet'), isTrue, reason: 'pointed at, a disabled button is still there');
    expect(walkSees(root, 'start-work'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('an automatic move does not turn straight back', () {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'One.', 'at': 'one', 'then': 'done'},
      <String, String>{'say': 'Two.', 'at': 'two'},
    ]);
    walk.read();
    // What one waits for appears: on it goes, by itself.
    walk.seen((key) => key == 'done');
    expect(walk.index, 1);
    // Now one is back and two gone: it would go back, but not so soon after going ahead.
    walk
      ..seen((key) => key == 'one')
      ..seen((key) => key == 'one');
    expect(walk.index, 1);
  });

  testWidgets('a step can wait for something to go', (tester) async {
    walkFile(<Map<String, String>>[
      <String, String>{'say': 'Close the dialog.', 'then': '!default-dialog'},
      <String, String>{'say': 'Done.'},
    ]);
    walk.read();
    await tester.pumpWidget(window());
    await tester.tap(find.byKey(const Key('start-work')));
    await tester.pump(const Duration(milliseconds: 500));
    walk.index = 0;
    await look(tester);
    expect(walk.index, 0, reason: 'the dialog is still open');

    Navigator.of(tester.element(find.byKey(const Key('default-dialog')))).pop();
    // A dialog leaves over two frames: its closing, then its removal.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await look(tester);
    expect(walk.index, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a button that carries no key is pointed at by what it says', (tester) async {
    await tester.pumpWidget(window());
    final root = tester.element(find.byType(Scaffold));
    expect(elementKeyed(root, 'text:Start work')?.widget.key, const Key('start-work'));
    expect(elementKeyed(root, 'text:Nothing says this'), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the state says buttons, fields and dialogs, and no secret', (tester) async {
    await tester.pumpWidget(window());
    final state = windowState(tester.element(find.byType(Scaffold)));

    expect(state, contains('Start work [start-work]'));
    expect(state, contains('Not yet [not-yet] (disabled)'));
    expect(state, contains('Its address [default-address]: "/home/me/my-first.git"'));
    expect(state, contains('Passphrase [passphrase]: (typed, hidden)'));
    expect(state, isNot(contains('not-for-anybody')));
    expect(state, isNot(contains('4711-secret')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('what the person says is written down with the state, and the answer comes back', (tester) async {
    await tester.pumpWidget(window());
    await tester.enterText(find.byKey(const Key('walk-comment')), 'Where is the repository?');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('walk-send')));
      // The window is drawn into an image off the test's clock; give it real time.
      for (var i = 0; i < 50 && !File('${folder.path}/comments.jsonl').existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pump();

    final written = jsonDecode(File('${folder.path}/comments.jsonl').readAsLinesSync().single) as Map<String, dynamic>;
    expect(written['text'], 'Where is the repository?');
    expect(written['state'], contains('Its address [default-address]'));
    expect(written['state'], isNot(contains('not-for-anybody')));
    expect(find.text('Where is the repository?'), findsOneWidget);
    expect(find.byKey(const Key('walk-answering')), findsOneWidget);
    // A secret is blanked only while the window is written down.
    expect(walkBlanking.value, isFalse);

    File('${folder.path}/answers.jsonl').writeAsStringSync('{"text": "It is the field at the top."}\n');
    walk.read();
    await tester.pump();
    expect(find.text('It is the field at the top.'), findsOneWidget);
    expect(find.byKey(const Key('walk-answering')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
