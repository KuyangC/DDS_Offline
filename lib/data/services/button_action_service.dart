import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'bell_manager.dart';

class ButtonActionService {
  static Future<String> handleMute(BuildContext context) async {
    final bellManager = GetIt.instance<BellManager>();
    await bellManager.toggleSystemMute();
    return bellManager.isSystemMuted ? 'Bell Muted' : 'Bell Resumed';
  }
}