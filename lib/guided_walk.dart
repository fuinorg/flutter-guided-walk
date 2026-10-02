/// Lets an AI agent guide a person through a Flutter app step by step: a panel beside the window, or
/// in a window of its own, that says what to do next, a ball on what to click, and a conversation
/// with the agent, which is sent the window's state as text and as an image, secrets blanked.
///
/// **Development builds only**, and only when started with a walk's folder: everything goes through
/// that folder on this computer and nowhere else. See the README for the walk file's format.
library;

export 'src/walk.dart' show WalkMessage, WalkSession, WalkStep;
export 'src/walk_frame.dart' show WalkFrame;
export 'src/walk_panel.dart' show WalkPanel, WalkPanelStyle, WalkPanelTexts, WalkPanelView;
export 'src/walk_secret.dart';
export 'src/walk_window.dart'
    show WalkWindowApp, WalkWindowHost, WalkWindowLayout, walkWindowLayoutFile, walkWindowPath, walkWindowSocket;
export 'src/window_state.dart' show WalkChoice, elementKeyed, walkChoices, walkSees, windowState;
