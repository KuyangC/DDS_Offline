import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import '../monitoring/offline_monitoring_page.dart';
import '../../../data/services/logger.dart';

class Login_page extends StatefulWidget {
  const Login_page({super.key});

  @override
  State<Login_page> createState() => _LoginPageState();
}

class _LoginPageState extends State<Login_page> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _setupPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  bool _obscureText = true;
  bool _isLoading = false;
  bool _isFirstTime = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _setupPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSetPin = prefs.containsKey('user_pin');
    setState(() {
      _isFirstTime = !hasSetPin;
    });
  }

  Future<void> _login() async {
    if (_pinController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Silakan masukkan PIN';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final prefs = await SharedPreferences.getInstance();
    final storedPin = prefs.getString('user_pin');

    if (storedPin == _pinController.text) {
      AppLogger.info('✅ Login successful');

      // Load configuration
      final ip = prefs.getString('ip') ?? '192.168.1.100';
      final port = prefs.getInt('port') ?? 81;
      final projectName = prefs.getString('projectName') ?? 'Default Project';
      final moduleCount = prefs.getInt('moduleCount') ?? 63;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => OfflineMonitoringPage(
            ip: ip,
            port: port,
            projectName: projectName,
            moduleCount: moduleCount,
          ),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'PIN salah';
      });
      AppLogger.warning('❌ Login failed: Incorrect PIN');

      // Shake animation
      _pinController.clear();
    }
  }

  Future<void> _setupPin() async {
    if (_setupPinController.text.isEmpty || _confirmPinController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Silakan lengkapi semua field';
      });
      return;
    }

    if (_setupPinController.text != _confirmPinController.text) {
      setState(() {
        _errorMessage = 'PIN tidak cocok';
      });
      return;
    }

    if (_setupPinController.text.length < 4) {
      setState(() {
        _errorMessage = 'PIN minimal 4 digit';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', _setupPinController.text);

    AppLogger.info('✅ PIN setup successful');

    // Load configuration
    final ip = prefs.getString('ip') ?? '192.168.1.100';
    final port = prefs.getInt('port') ?? 81;
    final projectName = prefs.getString('projectName') ?? 'Default Project';
    final moduleCount = prefs.getInt('moduleCount') ?? 63;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => OfflineMonitoringPage(
          ip: ip,
          port: port,
          projectName: projectName,
          moduleCount: moduleCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstTime) {
      return _buildSetupScreen();
    }

    return _buildLoginScreen();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo or Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.transparent,  // Hilang background biru
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/data/images/LOGO TEXT.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback ke icon jika gambar tidak ditemukan
                      return const Icon(
                        Icons.sensors,
                        size: 80,
                        color: Colors.blue,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'DDS Offline Monitoring',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Text(
                  'Fire Alarm Monitoring System',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // PIN Input Field
                TextField(
                  controller: _pinController,
                  obscureText: _obscureText,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: 'Masukkan PIN',
                    hintText: 'XXXX',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),

                // Login Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 24),

                // Version info
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Setup PIN'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.transparent,  // Hilang background biru
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/data/images/LOGO TEXT.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback ke icon jika gambar tidak ditemukan
                      return const Icon(
                        Icons.lock_person,
                        size: 80,
                        color: Colors.blue,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'Buat PIN Keamanan',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Text(
                  'Buat PIN untuk mengamankan aplikasi',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Setup PIN Field
                TextField(
                  controller: _setupPinController,
                  obscureText: _obscureText,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'PIN Baru',
                    hintText: 'Minimal 4 digit',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),

                // Confirm PIN Field
                TextField(
                  controller: _confirmPinController,
                  obscureText: _obscureText,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Konfirmasi PIN',
                    hintText: 'Ulangi PIN',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),

                // Setup Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _setupPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'BUAT PIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
