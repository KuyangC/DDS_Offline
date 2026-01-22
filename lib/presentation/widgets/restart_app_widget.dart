import 'package:flutter/material.dart';

/// Custom widget untuk restart aplikasi
/// Memberikan kemampuan hot restart tanpa perlu context yang rumit
class RestartAppWidget extends StatefulWidget {
  final Widget child;

  const RestartAppWidget({required this.child, super.key});

  @override
  State<RestartAppWidget> createState() => _RestartAppWidgetState();

  /// Method static untuk trigger restart dari mana saja
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartAppWidgetState>()?.restartApp();
  }
}

class _RestartAppWidgetState extends State<RestartAppWidget> {
  Key _key = UniqueKey();

  /// Method untuk restart aplikasi dengan mengganti key
  void restartApp() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
