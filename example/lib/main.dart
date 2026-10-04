import 'package:flutter/material.dart';
import 'package:guided_walk/guided_walk.dart';

/// A small app walked through: started with `GUIDED_WALK=<folder> flutter run -d linux`, it shows
/// the walk that folder's `walk.json` describes, beside the window.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Started by the walk as its window of its own: the panel and nothing else.
  if (walkWindowPath() case final path?) {
    runApp(WalkWindowApp(path));
    return;
  }
  runApp(ExampleApp(walk: WalkSession.fromEnvironment()?..start()));
}

/// The app, with a walk beside it where it was started with one.
class ExampleApp extends StatelessWidget {
  /// Constructor taking the walk, if there is one.
  const ExampleApp({this.walk, super.key});

  /// The walk, or null.
  final WalkSession? walk;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Guided walk example',
        // The banner sits over the top bar's corner, where the button that shows the walk is.
        debugShowCheckedModeBanner: false,
        // Around the navigator, so the panel stays usable while a dialog is open.
        builder: walk == null ? null : (context, child) => WalkFrame(walk: walk!, child: child!),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Guided walk example'),
            actions: <Widget>[
              // A walk put away comes back from here: without it, it stays away.
              if (walk case final walk?)
                ListenableBuilder(
                  listenable: walk,
                  builder: (context, _) => walk.hidden
                      ? IconButton(
                          key: const Key('walk-show'),
                          tooltip: 'Show the guided walk',
                          icon: const Icon(Icons.assistant_direction_outlined),
                          onPressed: walk.show,
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
          body: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const TextField(key: Key('name'), decoration: InputDecoration(labelText: 'Your name')),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('greet'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        key: const Key('greeting'),
                        title: const Text('Hello'),
                        actions: <Widget>[
                          TextButton(
                            key: const Key('greeting-close'),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Greet me'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
