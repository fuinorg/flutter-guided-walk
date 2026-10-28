import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guided_walk/guided_walk.dart';

/// The walk's panel in a window of its own: what the interface sends it, and what it sends back,
/// over a real socket, with a test standing in for the second window.
void main() {
  late Directory here;

  setUp(() async => here = await Directory.systemTemp.createTemp('guided-walk-window-'));
  tearDown(() async => here.delete(recursive: true));

  test('what the panel shows reaches it whole', () {
    const view = WalkPanelView(
      title: 'A first walk',
      steps: <String>['Click it.', 'Then this.'],
      index: 1,
      messages: <WalkMessage>[
        WalkMessage(fromThePerson: true, text: 'Done'),
        WalkMessage(fromThePerson: false, text: 'Good.'),
        WalkMessage(fromThePerson: false, fromTheWalk: true, text: 'Lost.'),
      ],
      waiting: true,
      pointsAtNothing: true,
      unread: true,
      sending: true,
    );
    final back = WalkPanelView.fromJson((jsonDecode(jsonEncode(view.toJson())) as Map).cast<String, Object?>());
    expect(back.toJson(), view.toJson());
    expect(back.current, 'Then this.');
    expect(back.messages.last.fromTheWalk, isTrue);
  });

  test('the window is shown what the walk shows, and what is pressed in it reaches the interface', () async {
    final commands = <Map<String, Object?>>[];
    final path = walkWindowSocket(here.path);
    late Socket window;
    var closed = 0;
    final host = WalkWindowHost(path, onCommand: commands.add, onClosed: () => closed++, start: (path) async {
      window = await Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);
      return null;
    });
    final opened = Completer<void>();
    host.addListener(() {
      if (host.open && !opened.isCompleted) opened.complete();
    });
    host.show(const WalkPanelView(title: 'Before the window', steps: <String>['One.']));
    await host.detach();
    await opened.future.timeout(const Duration(seconds: 5));
    // Kept: the next start opens the window again.
    expect(WalkWindowLayout.read(walkWindowLayoutFile(path)).detached, isTrue);
    expect(host.wasDetached, isTrue);
    final lines = window.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    final received = StreamIterator<String>(lines);

    // What was shown before the window came is what it shows first.
    expect(await received.moveNext(), isTrue);
    expect((jsonDecode(received.current) as Map)['title'], 'Before the window');

    // Shown again unchanged, nothing is sent; changed, it is.
    host
      ..show(const WalkPanelView(title: 'Before the window', steps: <String>['One.']))
      ..show(const WalkPanelView(title: 'Before the window', steps: <String>['One.'], index: 1));
    expect(await received.moveNext(), isTrue);
    expect((jsonDecode(received.current) as Map)['index'], 1);

    window.writeln(jsonEncode(<String, Object?>{'do': 'send', 'text': 'Hello', 'withText': true}));
    await window.flush();
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return commands.isEmpty;
    }).timeout(const Duration(seconds: 5));
    expect(commands.single, <String, Object?>{'do': 'send', 'text': 'Hello', 'withText': true});

    // Closing the window puts the panel back.
    window.destroy();
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return host.open;
    }).timeout(const Duration(seconds: 5));
    expect(host.open, isFalse);
    expect(closed, 0, reason: 'not yet: the interface may be going down with it');
    await Future<void>.delayed(WalkWindowHost.forgetAfter + const Duration(milliseconds: 200));
    expect(closed, 1, reason: 'closed by the person, the walk is put away');
    expect(host.wasDetached, isTrue, reason: 'and comes back in its window when shown');
    host.dispose();
    expect(File(path).existsSync(), isFalse, reason: 'the socket goes with the interface');
  });

  test('a window that does not answer is ended, one at a time, and the panel stays beside the interface', () async {
    final path = walkWindowSocket(here.path);
    final started = <Process>[];
    WalkWindowHost.answerWithin = const Duration(milliseconds: 300);
    addTearDown(() => WalkWindowHost.answerWithin = const Duration(seconds: 6));
    // Left in a window of its own last time.
    const WalkWindowLayout(detached: true).write(walkWindowLayoutFile(path));
    // A program that never opens the socket, as an app's executable rebuilt with other code.
    final host = WalkWindowHost(path, onCommand: (_) {}, start: (_) async {
      final process = await Process.start('sleep', const <String>['60']);
      started.add(process);
      return process;
    });
    await host.detach();
    await host.detach();
    await host.detach();
    expect(started, hasLength(1), reason: 'pressed again while the first is on its way, nothing more is started');
    await started.single.exitCode.timeout(const Duration(seconds: 5));
    expect(host.failed, isTrue, reason: 'the panel says so');
    expect(host.open, isFalse);
    expect(WalkWindowLayout.read(walkWindowLayoutFile(path)).detached, isFalse,
        reason: 'the next start does not wait for a window that never came');

    await host.detach();
    expect(host.failed, isFalse, reason: 'asked again, it is tried again');
    expect(started, hasLength(2));
    host.dispose();
    await started.last.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => fail('ended with the interface'));
  });

  test('a window that cannot be started leaves the panel beside the interface, and says so', () async {
    final path = walkWindowSocket(here.path);
    final host = WalkWindowHost(path, onCommand: (_) {}, start: (_) => Process.start('${here.path}/not-there', const <String>[]));
    await host.detach();
    expect(host.failed, isTrue);
    expect(WalkWindowLayout.read(walkWindowLayoutFile(path)).detached, isFalse);
    host.dispose();
  });

  testWidgets('a long step leaves the field to write in its lines', (tester) async {
    tester.view
      ..physicalSize = const Size(340, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final paragraph = List<String>.filled(30, 'paragraph').join(' ');
    final say = List<String>.filled(4, paragraph).join('\n\n');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkPanel(
          view: WalkPanelView(title: 'A long walk', steps: <String>[say, say, say], index: 2),
          onBack: () {},
          onNext: () {},
          onSend: (_, {required withText}) {},
        ),
      ),
    ));
    final field = find.descendant(of: find.byKey(const Key('walk-comment')), matching: find.byType(EditableText));
    final lineHeight = tester.widget<EditableText>(field).style.fontSize! * 1.4;
    expect(tester.getSize(field).height, greaterThanOrEqualTo(4 * lineHeight));
    expect(tester.getRect(find.byKey(const Key('walk-send'))).bottom, lessThanOrEqualTo(1000));
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });

  testWidgets('the font and size chosen in the panel are kept for the next panel', (tester) async {
    final file = File('${here.path}/panel-style.json');
    Widget panel() => MaterialApp(
          home: Scaffold(
            body: WalkPanel(
              view: const WalkPanelView(steps: <String>['Click it.']),
              onBack: () {},
              onNext: () {},
              onSend: (_, {required withText}) {},
              styleFile: file,
            ),
          ),
        );
    await tester.pumpWidget(panel());
    // A terminal's font, at its usual size, until something else is chosen.
    expect(WalkPanelStyle.read(file).font, 'monospace');
    final step = tester.widget<SelectableText>(find.byKey(const Key('walk-step')));
    expect(step.style?.fontFamily, 'monospace');

    await tester.tap(find.byKey(const Key('walk-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('walk-size Large')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('walk-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('walk-font Sans')));
    await tester.pumpAndSettle();

    final kept = WalkPanelStyle.read(file);
    expect(kept.scale, 1.2);
    expect(kept.font, 'sans-serif');
    double shown() => MediaQuery.of(tester.element(find.byKey(const Key('walk-step')))).textScaler.scale(10);
    expect(shown(), closeTo(12, 0.01));

    // Resting on a size shows it at once; leaving the menu without choosing puts back what was.
    await tester.tap(find.byKey(const Key('walk-style')));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey<String>('walk-size Largest'))));
    await tester.pumpAndSettle();
    expect(shown(), closeTo(17, 0.01));
    expect(WalkPanelStyle.read(file).scale, 1.2, reason: 'a preview is not kept');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shown(), closeTo(12, 0.01));
    await mouse.removePointer();
  });

  testWidgets('clearing the conversation is asked first', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkPanel(
          view: const WalkPanelView(messages: <WalkMessage>[WalkMessage(fromThePerson: true, text: 'Hello')]),
          onBack: () {},
          onNext: () {},
          onSend: (_, {required withText}) {},
          onClear: () => cleared++,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('walk-clear')));
    await tester.pump();
    expect(find.text('Clear the conversation?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('walk-clear-cancel')));
    await tester.pump();
    expect(cleared, 0, reason: 'kept when it is kept');
    expect(find.byKey(const Key('walk-clear-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('walk-clear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('walk-clear-confirm')));
    await tester.pump();
    expect(cleared, 1);
    expect(find.byKey(const Key('walk-clear-dialog')), findsNothing);
  });

  test('the window\'s size is kept with whether it is detached, and nonsense is not', () {
    final file = File('${here.path}/panel-window.json');
    const WalkWindowLayout(detached: true, width: 900, height: 700).write(file);
    final read = WalkWindowLayout.read(file);
    expect((read.detached, read.width, read.height), (true, 900, 700));
    read.copyWith(detached: false).write(file);
    expect(WalkWindowLayout.read(file).width, 900, reason: 'docking keeps the size for next time');
    file.writeAsStringSync('{"detached": true, "width": 5, "height": "tall"}');
    final odd = WalkWindowLayout.read(file);
    expect((odd.detached, odd.width, odd.height), (true, null, null));
  });

  test('a style file that cannot be read is the usual style', () {
    final file = File('${here.path}/panel-style.json')..writeAsStringSync('not json');
    expect(WalkPanelStyle.read(file).font, 'monospace');
    expect(WalkPanelStyle.read(file).scale, 1.0);
  });

  test('only a development build started for it is the walk window', () {
    expect(walkWindowPath(const <String, String>{}), isNull);
    expect(walkWindowPath(const <String, String>{'GUIDED_WALK_WINDOW': '/tmp/w.sock'}), '/tmp/w.sock');
  });
}
