
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'style.dart';
import 'walk.dart';

/// What the walk's panel shows: everything it needs, and nothing it would have to look up, so the
/// same panel is drawn beside the window or in a window of its own, fed over a socket.
@immutable
class WalkPanelView {
  /// Constructor taking every part of what is shown.
  const WalkPanelView({
    this.title = '',
    this.steps = const <String>[],
    this.index = 0,
    this.messages = const <WalkMessage>[],
    this.waiting = false,
    this.pointsAtNothing = false,
    this.unread = false,
    this.sending = false,
  });

  /// What the walk at hand shows of [walk], with what the frame found on screen.
  factory WalkPanelView.of(WalkSession walk, {bool pointsAtNothing = false, bool unread = false, bool sending = false}) =>
      WalkPanelView(
        title: walk.title,
        steps: <String>[for (final each in walk.steps) each.say],
        index: walk.index,
        messages: List<WalkMessage>.of(walk.messages),
        waiting: walk.waitingForAnAnswer,
        pointsAtNothing: pointsAtNothing,
        unread: unread,
        sending: sending,
      );

  /// As read from the socket.
  factory WalkPanelView.fromJson(Map<String, Object?> json) => WalkPanelView(
        title: json['title'] as String? ?? '',
        steps: <String>[for (final each in json['steps'] as List<Object?>? ?? const <Object?>[]) '$each'],
        index: json['index'] as int? ?? 0,
        messages: <WalkMessage>[
          for (final each in (json['messages'] as List<Object?>? ?? const <Object?>[]).cast<Map<String, Object?>>())
            WalkMessage(
              fromThePerson: each['fromThePerson'] == true,
              fromTheWalk: each['fromTheWalk'] == true,
              text: each['text'] as String? ?? '',
            ),
        ],
        waiting: json['waiting'] == true,
        pointsAtNothing: json['pointsAtNothing'] == true,
        unread: json['unread'] == true,
        sending: json['sending'] == true,
      );

  /// The walk's title.
  final String title;

  /// What each step says.
  final List<String> steps;

  /// The step shown now; the number of steps once the walk is through.
  final int index;

  /// What was said beside the walk, oldest first.
  final List<WalkMessage> messages;

  /// Whether the agent has not answered yet.
  final bool waiting;

  /// Whether the step points at something not on screen.
  final bool pointsAtNothing;

  /// Whether a terminal the walk never reads is on screen.
  final bool unread;

  /// Whether a comment is being sent.
  final bool sending;

  /// What the step shown now says, or null once the walk is through.
  String? get current => index < steps.length ? steps[index] : null;

  /// As written to the socket.
  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'steps': steps,
        'index': index,
        'messages': <Map<String, Object?>>[
          for (final each in messages)
            <String, Object?>{'fromThePerson': each.fromThePerson, 'fromTheWalk': each.fromTheWalk, 'text': each.text},
        ],
        'waiting': waiting,
        'pointsAtNothing': pointsAtNothing,
        'unread': unread,
        'sending': sending,
      };
}

/// How the panel's words are drawn: a font and a size, chosen in its menu and kept in the walk's
/// folder, so the panel beside the window and the one in its own window look alike. A terminal's
/// font by default.
@immutable
class WalkPanelStyle {
  /// Constructor taking the font and how much larger than usual.
  const WalkPanelStyle({this.font = 'monospace', this.scale = 1.0});

  /// The fonts offered, by family, with what they are called in the menu.
  static const fonts = <String, String>{'monospace': 'Terminal', 'sans-serif': 'Sans', 'serif': 'Serif'};

  /// The sizes offered, by factor, with what they are called in the menu.
  static final scales = <double, String>{0.85: 'Small', 1.0: 'Normal', 1.2: 'Large', 1.4: 'Larger', 1.7: 'Largest'};

  /// The font family.
  final String font;

  /// How much larger than usual.
  final double scale;

  /// Read from [file]; as it starts where there is none or it cannot be read.
  static WalkPanelStyle read(File? file) {
    try {
      if (file == null || !file.existsSync()) return const WalkPanelStyle();
      final json = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
      final font = json['font'] as String? ?? 'monospace';
      final scale = (json['scale'] as num?)?.toDouble() ?? 1.0;
      return WalkPanelStyle(
          font: fonts.containsKey(font) ? font : 'monospace', scale: scales.containsKey(scale) ? scale : 1.0);
    } on Object {
      return const WalkPanelStyle();
    }
  }

  /// Written to [file]; quiet where it cannot be: a font not kept is not worth an error.
  void write(File? file) {
    try {
      file?.writeAsStringSync(jsonEncode(<String, Object?>{'font': font, 'scale': scale}));
    } on Object {
      // Kept for this window only.
    }
  }

  /// With [font] or [scale] changed.
  WalkPanelStyle copyWith({String? font, double? scale}) =>
      WalkPanelStyle(font: font ?? this.font, scale: scale ?? this.scale);
}

/// The panel's words that an app may say in its own way, or in its people's language.
@immutable
class WalkPanelTexts {
  /// Constructor taking each, with an English default.
  const WalkPanelTexts({
    this.terminalUnread = 'A terminal is never read and never sent: what is typed there, a password '
        'say, stays here. So the walk does not see what was done in it; say so here when it does not '
        'go on by itself.',
  });

  /// Said while a terminal the walk never reads is on screen.
  final String terminalUnread;
}

/// The walk's panel: the step, the steps done, the conversation, and the field to write in.
class WalkPanel extends StatefulWidget {
  /// Constructor taking what is shown and what each button does.
  const WalkPanel({
    required this.view,
    required this.onBack,
    required this.onNext,
    required this.onSend,
    this.onDetach,
    this.onDock,
    this.styleFile,
    this.onClear,
    this.onClose,
    this.texts = const WalkPanelTexts(),
    super.key,
  });

  /// The panel's words that an app may say in its own way.
  final WalkPanelTexts texts;

  /// Puts the walk away; it is shown again from the window's top bar.
  final VoidCallback? onClose;

  /// Forgets the conversation; null where it cannot be.
  final VoidCallback? onClear;

  /// Where the font and size chosen are kept; null keeps them for this panel alone.
  final File? styleFile;

  /// What is shown.
  final WalkPanelView view;

  /// One step back.
  final VoidCallback onBack;

  /// One step on.
  final VoidCallback onNext;

  /// Sends what was written, or with [withText] false the window alone.
  final void Function(String text, {required bool withText}) onSend;

  /// Opens the panel in a window of its own; null where it already is one.
  final VoidCallback? onDetach;

  /// Puts the panel back beside the window; null where it is there.
  final VoidCallback? onDock;

  @override
  State<WalkPanel> createState() => _WalkPanelState();
}

class _WalkPanelState extends State<WalkPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  final TextEditingController _comment = TextEditingController();
  final ScrollController _conversation = ScrollController();
  int? _copiedAt;

  OverlayEntry? _question;

  /// Asks whether to clear the conversation, in the panel's own overlay: beside the window it has
  /// no navigator to show a dialog with.
  void _askToClear(BuildContext context, VoidCallback clear) {
    if (_question != null) return;
    void close() {
      _question?.remove();
      _question = null;
    }

    final entry = OverlayEntry(
      builder: (context) => Stack(
        children: <Widget>[
          ModalBarrier(dismissible: true, color: Colors.black38, onDismiss: close),
          Center(
            child: AlertDialog(
              key: const Key('walk-clear-dialog'),
              title: const Text('Clear the conversation?'),
              content: const Text('What was said beside the walk is forgotten, here and in the walk\'s folder. '
                  'The walk itself stays where it is.'),
              actions: <Widget>[
                TextButton(key: const Key('walk-clear-cancel'), onPressed: close, child: const Text('Keep it')),
                FilledButton(
                  key: const Key('walk-clear-confirm'),
                  onPressed: () {
                    close();
                    clear();
                  },
                  child: const Text('Clear it'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    _question = entry;
    Overlay.of(context).insert(entry);
  }
  late WalkPanelStyle _style = WalkPanelStyle.read(widget.styleFile);

  /// What the pointer rests on in the menu, shown at once and kept only when chosen.
  WalkPanelStyle? _preview;

  WalkPanelStyle get _shown => _preview ?? _style;

  WalkPanelView get view => widget.view;

  void _restyle(WalkPanelStyle style) {
    setState(() {
      _style = style;
      _preview = null;
    });
    style.write(widget.styleFile);
  }

  @override
  void didUpdateWidget(WalkPanel old) {
    super.didUpdateWidget(old);
    if (old.view.messages.length != view.messages.length || old.view.waiting != view.waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_conversation.hasClients) _conversation.jumpTo(_conversation.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _question?.remove();
    _pulse.dispose();
    _comment.dispose();
    _conversation.dispose();
    super.dispose();
  }

  /// The lines a step gives to copy: what stands between its first and last blank line.
  static String? _toCopy(String say) {
    final parts = say.split('\n\n');
    if (parts.length < 3) return null;
    return parts.sublist(1, parts.length - 1).join('\n\n');
  }

  void _send({bool withText = true}) {
    final text = withText ? _comment.text.trim() : '';
    if (withText && text.isEmpty) return;
    widget.onSend(text, withText: withText);
    if (withText) _comment.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_shown.scale)),
      child: Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: _shown.font),
          inputDecorationTheme: theme.inputDecorationTheme,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontFamily: _shown.font),
          child: Builder(builder: _panel),
        ),
      ),
    );
  }

  /// The font and size, chosen at the top of the panel; what the pointer rests on is shown at once.
  Widget _styleMenu() {
    MenuItemButton entry(String key, String label, WalkPanelStyle style, {required bool checked, TextStyle? look}) =>
        MenuItemButton(
          key: ValueKey<String>(key),
          leadingIcon: Icon(checked ? Icons.check : null, size: 18),
          onHover: (resting) => setState(() => _preview = resting ? style : null),
          onPressed: () => _restyle(style),
          child: Text(label, style: look),
        );
    return MenuAnchor(
      onClose: () => setState(() => _preview = null),
      menuChildren: <Widget>[
        for (final each in WalkPanelStyle.scales.entries)
          entry('walk-size ${each.value}', each.value, _style.copyWith(scale: each.key),
              checked: _style.scale == each.key),
        const Divider(),
        for (final each in WalkPanelStyle.fonts.entries)
          entry('walk-font ${each.value}', each.value, _style.copyWith(font: each.key),
              checked: _style.font == each.key, look: TextStyle(fontFamily: each.key)),
      ],
      builder: (context, menu, _) => IconButton(
        key: const Key('walk-style'),
        tooltip: 'Font and size',
        icon: const Icon(Icons.text_fields, size: 18),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final step = view.current;
    final toCopy = step == null ? null : _toCopy(step);
    return Material(
      key: const Key('walk-panel'),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(WalkSpace.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(view.title.isEmpty ? 'Guided walk' : view.title, style: text.titleSmall)),
                _styleMenu(),
                if (widget.onClear case final clear?)
                  IconButton(
                    key: const Key('walk-clear'),
                    tooltip: 'Clear the conversation',
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    onPressed: view.messages.isEmpty ? null : () => _askToClear(context, clear),
                  ),
                // A window of its own, beside the interface and as large as one likes; closing it, or this, puts it back.
                if (widget.onDetach case final detach?)
                  IconButton(
                    key: const Key('walk-detach'),
                    tooltip: 'Open the walk in a window of its own',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: detach,
                  ),
                if (widget.onClose case final close?)
                  IconButton(
                    key: const Key('walk-close'),
                    tooltip: 'Put the walk away (it comes back from the symbol in the top bar)',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: close,
                  ),
                if (widget.onDock case final dock?)
                  IconButton(
                    key: const Key('walk-dock'),
                    tooltip: 'Put the walk back beside the window',
                    icon: const Icon(Icons.vertical_split, size: 18),
                    onPressed: dock,
                  ),
              ],
            ),
            const SizedBox(height: WalkSpace.tight),
            // The steps already done stay readable: a step that moved on took its words with it, and
            // an address it named could no longer be read.
            if (view.index > 0)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (var done = 0; done < view.index && done < view.steps.length; done++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: WalkSpace.tight),
                          child: SelectableText(
                            '✓ ${done + 1}. ${view.steps[done]}',
                            key: ValueKey<String>('walk-done $done'),
                            style: text.bodySmall?.copyWith(color: scheme.outline),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // A long step scrolls in its box: grown with its words, it pushed the field to write in
            // below the window's edge.
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(WalkSpace.small),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  border: Border.all(color: Colors.deepOrange, width: 2),
                  borderRadius: BorderRadius.circular(WalkRadii.small),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SelectableText(
                        step == null
                            ? (view.steps.isEmpty ? 'Waiting for the walk…' : 'The walk is through.')
                            : 'Step ${view.index + 1} of ${view.steps.length}: $step'
                                '${view.pointsAtNothing ? '\n(What it points at is not on screen.)' : ''}',
                        key: const Key('walk-step'),
                        style: text.titleMedium?.copyWith(color: Colors.black87),
                      ),
                      // Lines to copy are a button away: selecting them showed no menu to copy with
                      //. The lines are what stands between blank lines.
                      if (toCopy case final lines?)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('walk-copy'),
                            icon: const Icon(Icons.copy, size: 18),
                            label: Text(_copiedAt == view.index ? 'Copied' : 'Copy the lines'),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: lines));
                              if (mounted) setState(() => _copiedAt = view.index);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // The person is told, not left to wonder why the walk does not follow them there.
            if (view.unread)
              Padding(
                padding: const EdgeInsets.only(top: WalkSpace.tight),
                child: Text(
                  widget.texts.terminalUnread,
                  key: const Key('walk-terminal-unread'),
                  style: text.bodySmall,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                    key: const Key('walk-back'),
                    onPressed: view.index == 0 ? null : widget.onBack,
                    child: const Text('Back')),
                FilledButton.tonal(
                    key: const Key('walk-next'),
                    onPressed: step == null ? null : widget.onNext,
                    child: const Text('Next')),
              ],
            ),
            const Divider(),
            Flexible(
              child: ListView(
                controller: _conversation,
                children: <Widget>[
                  for (final each in view.messages)
                    Align(
                      alignment: each.fromTheWalk
                          ? Alignment.center
                          : each.fromThePerson
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: WalkSpace.tight),
                        padding: const EdgeInsets.all(WalkSpace.small),
                        decoration: BoxDecoration(
                          color: each.fromTheWalk
                              ? Colors.transparent
                              : each.fromThePerson
                                  ? scheme.primaryContainer
                                  : scheme.surface,
                          borderRadius: BorderRadius.circular(WalkRadii.small),
                        ),
                        child: SelectableText(each.text,
                            style: each.fromTheWalk
                                ? text.bodySmall?.copyWith(color: scheme.outline, fontStyle: FontStyle.italic)
                                : null),
                      ),
                    ),
                  // Said, not left to be guessed: the agent is reading and answering.
                  if (view.waiting)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => Container(
                          key: const Key('walk-answering'),
                          margin: const EdgeInsets.symmetric(vertical: WalkSpace.tight),
                          padding: const EdgeInsets.symmetric(horizontal: WalkSpace.normal, vertical: WalkSpace.small),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(WalkRadii.small),
                          ),
                          child: Opacity(
                            opacity: 0.3 + 0.7 * _pulse.value,
                            child: Text('…', style: text.titleLarge),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('walk-comment'),
              controller: _comment,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What you find',
                helperText: 'Sent with the window as text and as an image, secrets blanked.',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: WalkSpace.tight),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                  key: const Key('walk-send-window'),
                  onPressed: view.sending ? null : () => _send(withText: false),
                  child: const Text('Send the window only'),
                ),
                FilledButton(
                  key: const Key('walk-send'),
                  onPressed: view.sending ? null : _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
