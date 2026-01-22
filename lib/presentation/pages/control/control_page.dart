import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../../providers/fire_alarm_data_provider.dart';
import '../../widgets/unified_status_bar.dart';

class ControlPage extends StatefulWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final String? username;
  const ControlPage({super.key, this.scaffoldKey, this.username});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  // Fungsi untuk menghitung ukuran font berdasarkan rasio layar
  double _calculateFontSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diagonal = math.sqrt(
      math.pow(size.width, 2) + math.pow(size.height, 2),
    );

    // Rasio berdasarkan diagonal layar
    final baseSize = diagonal / 100;

    // Batasi ukuran font antara 8.0 dan 15.0
    return baseSize.clamp(8.0, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    // Hitung ukuran font dasar berdasarkan layar
    final baseFontSize = _calculateFontSize(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            // Unified Status Bar - Synchronized across all pages
            FullStatusBar(scaffoldKey: widget.scaffoldKey),

            // Control buttons have been removed
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.block,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Control Panel Disabled',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Control buttons have been removed from this page',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Footer info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '© 2025 DDS Fire Alarm System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: baseFontSize * 0.8,
                  color: Colors.grey[600],
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
