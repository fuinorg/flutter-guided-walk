import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'style.dart';
import 'walk.dart';
import 'walk_panel.dart';
import 'walk_secret.dart';
import 'walk_window.dart';
import 'window_state.dart';

/// The interface with a guided walk beside it: a bubble pointing at the step's element, and a
/// panel docked at the right edge, beside the window rather than over it, for the conversation.
class WalkFrame extends StatefulWidget {
  /// Constructor taking the walk and the window it walks through.
  const WalkFrame({required this.walk, required this.child, this.texts = const WalkPanelTexts(), super.key});

  /// The panel's words that an app may say in its own way.
  final WalkPanelTexts texts;

  /// The walk.
  final WalkSession walk;

  /// The window, as the application draws it.
  final Widget child;

  /// How wide the panel beside the window is.
  static const panelWidth = 340.0;

  @override
  State<WalkFrame> createState() => _WalkFrameState();
}

class _WalkFrameState extends State<WalkFrame> with SingleTickerProviderStateMixin {
  /// The ball on what to click, pulsing so the eye finds it.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  final GlobalKey _window = GlobalKey(debugLabel: 'the window, for a walk');
  final GlobalKey _stack = GlobalKey(debugLabel: 'where the bubble is drawn');
  Timer? _looking;
  Rect? _target;
  bool _sending = false;

  /// Whether a terminal the walk never reads is on screen, which the panel says.
  bool _unread = false;

  /// The step whose element was last brought into view.
  int? _shown;

  /// The panel's window of its own, once it was asked for.
  WalkWindowHost? _window2;

  WalkSession get walk => widget.walk;

  @override
  void initState() {
    super.initState();
    walk
      ..addListener(_changed)
      // An agent asking to see the window gets what a message would carry, secrets blanked.
      ..onLook = () async {
        final root = _root;
        final image = await _picture();
        return (state: root == null ? '' : windowState(root), image: image == null ? null : Uint8List.fromList(image));
      }
      ..onLost = () => unawaited(_send(
          byTheWalk: true,
          said: 'The walk lost its way: step ${walk.index + 1} points at something not on screen. The '
              'agent looks at the window.'));
    // As it was left: put away, or in a window of its own.
    final layout = WalkWindowLayout.read(walkWindowLayoutFile(walkWindowSocket(walk.folder.path)));
    walk.startHidden(layout.hidden);
    _wasHidden = layout.hidden;
    if (!layout.hidden && layout.detached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_detach());
      });
    }
    // Looked at again and again: what a step points at moves, opens and closes as the person works.
    _looking = Timer.periodic(const Duration(milliseconds: 400), (_) => _look());
  }

  @override
  void dispose() {
    walk
      ..removeListener(_changed)
      ..onLook = null;
    _looking?.cancel();
    _pulse.dispose();
    _window2?.dispose();
    super.dispose();
  }

  bool _wasHidden = false;

  void _changed() {
    if (!mounted) return;
    if (walk.hidden != _wasHidden) {
      _wasHidden = walk.hidden;
      final file = walkWindowLayoutFile(walkWindowSocket(walk.folder.path));
      final layout = WalkWindowLayout.read(file);
      layout.copyWith(hidden: walk.hidden).write(file);
      if (walk.hidden) {
        _window2?.close();
        _target = null;
      } else if (layout.detached) {
        unawaited(_detach());
      }
    }
    setState(() {});
  }

  WalkWindowHost _host() => _window2 ??=
      WalkWindowHost(walkWindowSocket(walk.folder.path), onCommand: _command, onClosed: walk.hide)
        ..addListener(_changed);

  Future<void> _detach() => _host().detach();

  void _command(Map<String, Object?> command) {
    switch (command['do']) {
      case 'back':
        walk.back();
      case 'next':
        walk.next();
      case 'send':
        unawaited(_send(said: command['text'] as String? ?? '', withText: command['withText'] != false));
      case 'clear':
        walk.clearConversation();
      case 'close':
        walk.hide();
      case 'dock':
        _window2?.dock();
    }
  }

  Element? get _root => _window.currentContext as Element?;

  /// Whether what a key names is on screen. The panel's own elements are, wherever the panel is:
  /// it sits beside the window the walk looks at, or in a window of its own, and a step pointing at
  /// its menu was taken for lost.
  bool Function(String key) _onScreen(Element root) {
    final detached = _window2?.open ?? false;
    return (key) {
      final bare = key.replaceFirst(RegExp('^(usable:|filled:)'), '');
      if (bare.startsWith('walk-')) return bare != (detached ? 'walk-detach' : 'walk-dock');
      return walkSees(root, key);
    };
  }

  /// Finds what the step points at, and moves on when what it waits for has appeared.
  void _look() {
    final root = _root;
    if (root == null || !mounted || walk.hidden) return;
    // Something visibly at work — a start building its image, a script running — is not a walk that
    // lost its way.
    var working = false;
    void spin(Element each) {
      if (working) return;
      if (each.widget is ProgressIndicator) {
        working = true;
        return;
      }
      each.visitChildElements(spin);
    }

    spin(root);
    walk.seen(_onScreen(root), working: working);
    final step = walk.current;
    Rect? rect;
    if (step != null && step.at.isNotEmpty) {
      final element = step.at.map((key) => elementKeyed(root, key)).nonNulls.firstOrNull;
      // Brought into view once when the step begins: a button below the fold was pointed at, and
      // not seen.
      if (element != null && _shown != walk.index) {
        _shown = walk.index;
        unawaited(Scrollable.ensureVisible(element, duration: const Duration(milliseconds: 200), alignment: 0.5));
      }
      final box = element?.findRenderObject();
      final stack = _stack.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached && stack is RenderBox) {
        final topLeft = box.localToGlobal(Offset.zero, ancestor: stack);
        rect = topLeft & box.size;
      }
    }
    var unread = false;
    void find(Element each) {
      if (unread) return;
      if (each.widget is WalkSecret) {
        unread = true;
        return;
      }
      each.visitChildElements(find);
    }

    find(root);
    if (rect != _target || unread != _unread) {
      setState(() {
        _target = rect;
        _unread = unread;
      });
    }
  }

  /// The window as an image, with every secret blanked first; null when it could not be taken.
  Future<List<int>?> _picture() async {
    final boundary = _window.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    walkBlanking.value = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png?.buffer.asUint8List();
    } on Object {
      return null;
    } finally {
      walkBlanking.value = false;
    }
  }

  /// Sends [said] with the window as text and as an image; with [withText] false, the window alone.
  Future<void> _send({String said = '', bool withText = true, bool byTheWalk = false}) async {
    final text = withText ? said : '';
    setState(() => _sending = true);
    final root = _root;
    final state = root == null ? '' : windowState(root);
    final image = await _picture();
    await walk.comment(text,
        state: state, image: image == null ? null : Uint8List.fromList(image), byTheWalk: byTheWalk);
    if (!mounted) return;
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final step = walk.current;
    final view = WalkPanelView.of(walk,
        pointsAtNothing: step != null && step.at.isNotEmpty && _target == null, unread: _unread, sending: _sending);
    final detached = _window2?.open ?? false;
    if (detached) _window2!.show(view);
    return Row(
      children: <Widget>[
        Expanded(
          child: Stack(
            key: _stack,
            children: <Widget>[
              // Looked at again right after every click as well, not only on the clock: what the
              // click did is what the walk follows.
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerUp: (_) {
                    for (final after in const <int>[50, 250]) {
                      Future<void>.delayed(Duration(milliseconds: after), _look);
                    }
                  },
                  child: RepaintBoundary(key: _window, child: widget.child),
                ),
              ),
              if (step != null && _target != null && !walk.hidden) ...<Widget>[
                // A frame around what the step points at, which never takes a click from it.
                Positioned.fromRect(
                  rect: _target!.inflate(4),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('walk-target'),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.deepOrange, width: 3),
                        borderRadius: BorderRadius.circular(WalkRadii.small),
                      ),
                    ),
                  ),
                ),
                // A bright ball pulsing on what to click: the frame alone was easy to miss.
                Positioned(
                  // At the right edge of what to click, so it never hides what it says.
                  left: _target!.right - 18,
                  top: _target!.center.dy - 18,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => SizedBox.square(
                        key: const Key('walk-ball'),
                        dimension: 36,
                        child: Center(
                          child: Container(
                            width: 14 + 22 * _pulse.value,
                            height: 14 + 22 * _pulse.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.orangeAccent.withValues(alpha: 0.85 - 0.45 * _pulse.value),
                              border: Border.all(color: Colors.deepOrange, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The sentence is in the panel, not over the window: a bubble hid what it pointed near
                //.
              ],
            ],
          ),
        ),
        // Beside the window, unless it was given a window of its own or put away. The window
        // itself stays where it is in the tree either way, so nothing in it starts again.
        if (!detached && !walk.hidden)
          SizedBox(
            width: WalkFrame.panelWidth,
            // Outside the navigator, so it has an overlay of its own for its text field.
            child: Overlay.wrap(
              child: WalkPanel(
                view: view,
                onBack: walk.back,
                onNext: walk.next,
                onSend: (text, {required withText}) => unawaited(_send(said: text, withText: withText)),
                onDetach: () => unawaited(_detach()),
                onClear: walk.clearConversation,
                onClose: walk.hide,
                texts: widget.texts,
                styleFile: File('${walk.folder.path}/panel-style.json'),
              ),
            ),
          ),
      ],
    );
  }
}
