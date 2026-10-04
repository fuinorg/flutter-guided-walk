import 'package:flutter/material.dart';

/// Whether what is secret on screen is being blanked, while the window is written down for a walk.
final ValueNotifier<bool> walkBlanking = ValueNotifier<bool>(false);

/// Something that may show a secret — a terminal where a sign-in code or a passphrase appears —
/// blanked whenever the window is written down for a walk, and left out of its state.
class WalkSecret extends StatelessWidget {
  /// Constructor taking what may show a secret.
  const WalkSecret({required this.child, super.key});

  /// What may show a secret.
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: walkBlanking,
        builder: (context, blanking, child) => Stack(
          children: <Widget>[
            child!,
            if (blanking)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text('(hidden for the walk)', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
        child: child,
      );
}
