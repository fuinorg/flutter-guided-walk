import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guided_walk/src/mcp/walk_mcp.dart';

/// The MCP server over the walk's files, as an agent meets it: JSON-RPC in, JSON-RPC out.
void main() {
  late Directory folder;
  late StreamController<String> input;
  late StringBuffer output;
  late Future<void> served;
  var id = 0;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('guided-walk-mcp-');
    // The app showing the walk: this test's own process, which runs.
    File('${folder.path}/status.json')
        .writeAsStringSync(jsonEncode(<String, Object?>{'pid': pid, 'program': Platform.resolvedExecutable}));
    WalkMcpServer.pollEvery = const Duration(milliseconds: 10);
    WalkMcpServer.lookTimeout = const Duration(seconds: 2);
  });

  tearDown(() async {
    await input.close();
    await served;
    folder.deleteSync(recursive: true);
  });

  void start() {
    input = StreamController<String>();
    output = StringBuffer();
    served = WalkMcpServer(folder).serve(input.stream, output);
  }

  /// Sends a request and waits for its answer.
  Future<Map<String, Object?>> ask(String method, [Map<String, Object?>? params]) async {
    final mine = ++id;
    input.add(jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': mine, 'method': method, 'params': ?params}));
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (final line in const LineSplitter().convert(output.toString())) {
        final answer = (jsonDecode(line) as Map).cast<String, Object?>();
        if (answer['id'] == mine) return answer;
      }
    }
  }

  Future<Map<String, Object?>> call(String tool, [Map<String, Object?> arguments = const <String, Object?>{}]) async =>
      ((await ask('tools/call', <String, Object?>{'name': tool, 'arguments': arguments}))['result']! as Map)
          .cast<String, Object?>();

  List<Map<String, Object?>> content(Map<String, Object?> result) =>
      (result['content']! as List).cast<Map<Object?, Object?>>().map((each) => each.cast<String, Object?>()).toList();

  test('it says what it is and which tools it has, and answers the version it was asked for', () async {
    start();
    final hello = await ask('initialize', <String, Object?>{'protocolVersion': '2025-03-26'});
    expect((hello['result']! as Map)['protocolVersion'], '2025-03-26');
    final tools = ((await ask('tools/list'))['result']! as Map)['tools']! as List;
    expect([for (final each in tools) (each as Map)['name']],
        <String>['walk_status', 'walk_set', 'walk_say', 'walk_wait', 'walk_look']);
    expect((await ask('no/such'))['error'], containsPair('code', -32601));
  });

  test('a walk and an answer are written where the app reads them', () async {
    start();
    await call('walk_set', <String, Object?>{
      'title': 'A walk',
      'steps': <Object?>[
        <String, Object?>{'say': 'Click it.', 'at': 'go'},
      ],
      'from': 0,
    });
    final walk = jsonDecode(File('${folder.path}/walk.json').readAsStringSync()) as Map;
    expect(walk['title'], 'A walk');
    expect(walk['from'], 0);
    expect(File('${folder.path}/walk.json.part').existsSync(), isFalse, reason: 'written whole, then moved');

    final refused = await call('walk_set', <String, Object?>{
      'title': 'Broken',
      'steps': <Object?>[<String, Object?>{'at': 'go'}],
    });
    expect(refused['isError'], isTrue);

    await call('walk_say', <String, Object?>{'text': 'Hello.'});
    expect(File('${folder.path}/answers.jsonl').readAsStringSync(), '{"text":"Hello."}\n');
  });

  test('waiting returns what the person said after the server started, with the window', () async {
    File('${folder.path}/comments.jsonl').writeAsStringSync('${jsonEncode(<String, Object?>{'text': 'Said before.'})}\n');
    start();
    expect(content(await call('walk_wait', <String, Object?>{'timeout_seconds': 0})).single['text'],
        contains('Nothing was said'));

    File('${folder.path}/window-1.png').writeAsBytesSync(<int>[1, 2, 3]);
    File('${folder.path}/comments.jsonl').writeAsStringSync(
        '${jsonEncode(<String, Object?>{'text': 'It is grey.', 'step': 2, 'stepSays': 'Click it.', 'state': 'Buttons: Go', 'image': 'window-1.png'})}\n',
        mode: FileMode.append);
    final said = content(await call('walk_wait', <String, Object?>{'timeout_seconds': 5}));
    expect(said.first['text'], allOf(contains('The person said: It is grey.'), contains('At step 2'), contains('Buttons: Go')));
    expect(said.last, <String, Object?>{'type': 'image', 'data': base64Encode(<int>[1, 2, 3]), 'mimeType': 'image/png'});
    expect(said.any((each) => '${each['text']}'.contains('Said before')), isFalse);
  });

  test('what is said between the start and the first wait is not taken for old', () async {
    start();
    await ask('ping');
    File('${folder.path}/comments.jsonl').writeAsStringSync('${jsonEncode(<String, Object?>{'text': 'Quick.'})}\n');
    expect(content(await call('walk_wait', <String, Object?>{'timeout_seconds': 1})).first['text'], contains('Quick.'));
  });

  test('a server started again goes on where the last one stopped, and loses nothing said between', () async {
    start();
    await ask('ping');
    await input.close();
    await served;
    // Said while no server runs, as when the agent's session starts again.
    File('${folder.path}/comments.jsonl').writeAsStringSync('${jsonEncode(<String, Object?>{'text': 'Hallo'})}\n');
    start();
    expect(content(await call('walk_wait', <String, Object?>{'timeout_seconds': 1})).first['text'], contains('Hallo'));
    await input.close();
    await served;
    start();
    expect(content(await call('walk_wait', <String, Object?>{'timeout_seconds': 0})).single['text'],
        contains('Nothing was said'), reason: 'handed over once');
  });

  test('while the walk is put away, every tool says so first', () async {
    start();
    File('${folder.path}/status.json').writeAsStringSync(
        jsonEncode(<String, Object?>{'pid': pid, 'program': Platform.resolvedExecutable, 'hidden': true}));
    final said = content(await call('walk_say', <String, Object?>{'text': 'Hello.'}));
    expect(said.first['text'], contains('put the walk away'));
    expect(said.last['text'], 'Said.');
    File('${folder.path}/status.json').writeAsStringSync(
        jsonEncode(<String, Object?>{'pid': pid, 'program': Platform.resolvedExecutable, 'hidden': false}));
    expect(content(await call('walk_say', <String, Object?>{'text': 'Again.'})).single['text'], 'Said.');
  });

  test('an app that is gone ends the wait and is said by every tool', () async {
    // A process that has ended: its number names nothing any more.
    final ended = await Process.start('true', const <String>[]);
    await ended.exitCode;
    File('${folder.path}/status.json').writeAsStringSync(jsonEncode(<String, Object?>{'pid': ended.pid}));
    start();
    final waited = DateTime.now();
    final said = content(await call('walk_wait', <String, Object?>{'timeout_seconds': 60}));
    expect(DateTime.now().difference(waited), lessThan(const Duration(seconds: 5)), reason: 'not the whole minute');
    expect(said.first['text'], contains('The app is not running'));
    expect(said.last['text'], contains('Nothing more will be said'));
  });

  test('a look asks the app and returns what it answered', () async {
    start();
    final looking = call('walk_look');
    // The app's side: a request, answered once.
    final request = File('${folder.path}/look-request.json');
    while (!request.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final n = (jsonDecode(request.readAsStringSync()) as Map)['n'];
    File('${folder.path}/look-1.png').writeAsBytesSync(<int>[9]);
    File('${folder.path}/look.json').writeAsStringSync(
        jsonEncode(<String, Object?>{'n': n, 'step': 0, 'stepSays': 'Click it.', 'state': 'Fields: none', 'image': 'look-1.png'}));
    final seen = content(await looking);
    expect(seen.first['text'], contains('Fields: none'));
    expect(seen.last['type'], 'image');
  });

  test('a look nobody answers says so', () async {
    WalkMcpServer.lookTimeout = const Duration(milliseconds: 100);
    start();
    final result = await call('walk_look');
    expect(result['isError'], isTrue);
    expect(content(result).single['text'], contains('did not show its window'));
  });
}
