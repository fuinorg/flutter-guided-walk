import 'package:flutter/material.dart';

import 'walk_secret.dart';

/// The window's state as text, for the agent leading a walk: the dialogs open, every button and
/// whether it can be pressed, every field and what it holds, and what the window says.
///
/// **No secret is in it**: an obscured field says only that something is typed, and nothing under a
/// [WalkSecret] is read at all.
String windowState(Element root) {
  final dialogs = <String>[];
  final buttons = <String>[];
  final fields = <String>[];
  final says = <String>[];
  final seen = <String>{};

  String keyOf(Widget widget) => switch (widget.key) {
        ValueKey<String>(:final value) => ' [$value]',
        _ => '',
      };

  String textsUnder(Element element) {
    final found = <String>[];
    void visit(Element each) {
      final widget = each.widget;
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        if (text.trim().isNotEmpty) found.add(text.trim());
      }
      each.visitChildElements(visit);
    }

    visit(element);
    return found.join(' ');
  }

  void visit(Element element) {
    final widget = element.widget;
    if (widget is WalkSecret) {
      says.add('(a terminal, hidden for the walk)');
      return;
    }
    switch (widget) {
      case AlertDialog(:final title?):
        dialogs.add(textsUnder(_firstOf(element, title) ?? element));
      case ButtonStyleButton(:final onPressed):
        buttons.add('${textsUnder(element)}${keyOf(widget)}${onPressed == null ? ' (disabled)' : ''}');
        return;
      case IconButton(:final onPressed, :final tooltip):
        buttons.add('${tooltip ?? 'an icon'}${keyOf(widget)}${onPressed == null ? ' (disabled)' : ''}');
        return;
      case TextField(:final obscureText, :final decoration):
        final label = decoration?.labelText ?? decoration?.hintText ?? 'a field';
        final value = typedIn(element);
        fields.add('$label${keyOf(widget)}: ${obscureText ? (value.isEmpty ? '(empty, hidden)' : '(typed, hidden)') : value.isEmpty ? '(empty)' : '"$value"'}');
        return;
      case Text():
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        if (text.trim().isNotEmpty && seen.add(text.trim())) says.add(text.trim());
    }
    element.visitChildElements(visit);
  }

  visit(root);
  return <String>[
    if (dialogs.isNotEmpty) 'Dialogs open: ${dialogs.join(' | ')}',
    'Buttons:',
    for (final each in buttons) '- $each',
    'Fields:',
    for (final each in fields) '- $each',
    'The window says:',
    for (final each in says) '- $each',
  ].join('\n');
}

/// The element of [widget] under [element], or null.
Element? _firstOf(Element element, Widget widget) {
  Element? found;
  void visit(Element each) {
    if (found != null) return;
    if (identical(each.widget, widget)) {
      found = each;
      return;
    }
    each.visitChildElements(visit);
  }

  visit(element);
  return found;
}

/// The element whose widget carries the key [key], or null when nothing on screen does. A `*` in
/// [key] stands for anything, as in `project */default`, the row of default under whichever machine.
/// `text:<words>` is the button that says those words, for one that carries no key: the last one, as
/// a dialog's is drawn over everything else.
Element? elementKeyed(Element root, String key) {
  // Behind an open dialog nothing can be clicked, so nothing there counts as on screen.
  root = topDialog(root) ?? root;
  if (key.startsWith('text:')) return _buttonSaying(root, key.substring('text:'.length));
  final pattern = key.contains('*')
      ? RegExp('^${key.split('*').map(RegExp.escape).join('.*')}\$')
      : null;
  bool wanted(Key? each) => pattern == null
      ? each == ValueKey<String>(key)
      : each is ValueKey<String> && pattern.hasMatch(each.value);
  Element? found;
  void visit(Element each) {
    if (found != null) return;
    if (wanted(each.widget.key)) {
      found = each;
      return;
    }
    each.visitChildElements(visit);
  }

  visit(root);
  return found;
}

/// The dialog on top, or null when none is open.
///
/// The outermost dialog widget of the last one in the tree: an `AlertDialog` draws a `Dialog`
/// inside it, and the key a step names may be on either.
Element? topDialog(Element root) {
  Element? dialog;
  void find(Element each, bool inside) {
    final isDialog = each.widget is Dialog || each.widget is AlertDialog || each.widget is SimpleDialog;
    if (isDialog && !inside) dialog = each;
    each.visitChildElements((child) => find(child, inside || isDialog));
  }

  find(root, false);
  return dialog;
}

Element? _buttonSaying(Element root, String words) {
  Element? found;
  void visit(Element each) {
    final widget = each.widget;
    // A button, a list's row or a menu's entry: whatever a person presses by its words.
    if (widget is ButtonStyleButton || widget is ListTile) {
      var says = false;
      void look(Element inner) {
        final text = inner.widget;
        if (text is Text && (text.data ?? '').trim() == words) says = true;
        inner.visitChildElements(look);
      }

      look(each);
      final box = each.findRenderObject();
      if (says && box is RenderBox && box.attached && box.hasSize) found = each;
    }
    each.visitChildElements(visit);
  }

  visit(root);
  return found;
}

/// What is typed in the text field at [element]. A field given no controller by the app keeps its
/// text in one of its own, which only the editable text inside it holds: read from the app's alone,
/// such a field was said to be empty while it showed a name.
String typedIn(Element element) {
  final field = element.widget;
  if (field is TextField && field.controller != null) return field.controller!.text;
  String? found;
  void look(Element each) {
    if (found != null) return;
    final widget = each.widget;
    if (widget is EditableText) {
      found = widget.controller.text;
      return;
    }
    each.visitChildElements(look);
  }

  element.visitChildElements(look);
  return found ?? '';
}

/// Whether a widget of the app's own is a choice that was made: true or false where it is one, null
/// where it is not. An app with choice widgets of its own adds a test for them to [walkChoices], so a
/// step waiting for `filled:<key>` sees them filled.
typedef WalkChoice = bool? Function(Widget widget);

/// The tests for choices of the app's own; checkboxes are known already.
final List<WalkChoice> walkChoices = <WalkChoice>[];

bool? _chosen(Widget widget) {
  if (widget is CheckboxListTile) return widget.value == true;
  if (widget is Checkbox) return widget.value == true;
  for (final each in walkChoices) {
    final made = each(widget);
    if (made != null) return made;
  }
  return null;
}

/// Whether what [key] names is on screen, or, as `filled:<key>`, holds something: a text field with
/// text, a choice made. A step on a form waits for that, not for the next field to appear, which is
/// there from the start.
bool walkSees(Element root, String key) {
  // A button that can no longer be pressed is done with: a step waiting for it to go moves on
  //.
  // Only as `usable:<key>`, what a step waiting for something to go asks: a disabled button pointed
  // at is still there, and taking it as gone made the walk say it was lost while the person looked
  // at it.
  if (key.startsWith('usable:')) {
    final element = elementKeyed(root, key.substring('usable:'.length));
    final widget = element?.widget;
    if (widget is ButtonStyleButton && !widget.enabled) return false;
    return element != null;
  }
  if (!key.startsWith('filled:')) return elementKeyed(root, key) != null;
  final element = elementKeyed(root, key.substring('filled:'.length));
  if (element == null) return false;
  var filled = false;
  void look(Element each) {
    final widget = each.widget;
    if (widget is TextField && typedIn(each).trim().isNotEmpty) filled = true;
    if (_chosen(widget) == true) filled = true;
    if (!filled) each.visitChildElements(look);
  }

  look(element);
  if (!filled) {
    // A choice carries its key a little below itself, at times: it is looked for above as well.
    var levels = 0;
    element.visitAncestorElements((above) {
      final made = _chosen(above.widget);
      if (made != null) {
        filled = made;
        return false;
      }
      return ++levels < 8;
    });
  }
  return filled;
}
