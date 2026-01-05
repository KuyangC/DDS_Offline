import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/datasources/local/exit_password_service.dart';

/// Dialog widget for entering exit password to leave OfflineMonitoringPage
/// Provides a user-friendly 4-digit PIN input interface with visual feedback
class ExitPasswordDialog extends StatefulWidget {
  final Function(bool) onResult; // true = password correct, false = cancelled

  const ExitPasswordDialog({
    super.key,
    required this.onResult,
  });

  @override
  State<ExitPasswordDialog> createState() => _ExitPasswordDialogState();
}

class _ExitPasswordDialogState extends State<ExitPasswordDialog>
    with TickerProviderStateMixin {
  String _passwordInput = '';
  bool _isShaking = false;
  String _errorMessage = '';
  bool _passwordValidated = false;  // NEW: Track validation state
  bool _isConfirming = false;       // NEW: Track confirmation state

  late TextEditingController _passwordController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize password controller
    _passwordController = TextEditingController();

    // Initialize shake animation for wrong password feedback
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Initialize password service
    _initializePasswordService();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _initializePasswordService() async {
    await ExitPasswordService.initializePassword();
  }

  void _validatePassword() {
    if (ExitPasswordService.validatePassword(_passwordInput)) {
      // Password correct - move to confirmation state
      HapticFeedback.lightImpact();
      setState(() {
        _passwordValidated = true;
        _isConfirming = true;
      });
      // DO NOT call widget.onResult(true) immediately - wait for confirmation
    } else {
      // Password wrong - error feedback
      _showError();
    }
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    setState(() {
      _errorMessage = 'Incorrect password';
      _isShaking = true;
    });

    // Start shake animation
    _shakeController.forward().then((_) {
      _shakeController.reverse();
    });

    // Reset state after animation
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isShaking = false;
        });
      }
    });

    // Clear password input after delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _passwordInput = '';
          _errorMessage = '';
        });
        _passwordController.clear();
      }
    });
  }

  void _onCancel() {
    HapticFeedback.lightImpact();
    widget.onResult(false);
    Navigator.of(context).pop();
  }

  // NEW: Confirmation methods for enhanced flow
  void _confirmExit() {
    HapticFeedback.heavyImpact();  // Strong haptic for final confirmation
    widget.onResult(true);
    Navigator.of(context).pop();
  }

  void _cancelConfirmation() {
    HapticFeedback.lightImpact();
    setState(() {
      _passwordInput = '';
      _passwordValidated = false;
      _isConfirming = false;
      _errorMessage = '';
    });
    _passwordController.clear();
  }

  Widget _buildPasswordDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _errorMessage.isNotEmpty ? Colors.red.shade300 : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            'EXIT PASSWORD',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final hasDigit = index < _passwordInput.length;
              return Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasDigit ? Colors.blue.shade600 : Colors.transparent,
                  border: Border.all(
                    color: hasDigit ? Colors.blue.shade600 : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: hasDigit
                    ? const Icon(
                        Icons.circle,
                        color: Colors.white,
                        size: 8,
                      )
                    : null,
              );
            }),
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.red.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // NEW: Confirmation UI section
  Widget _buildConfirmationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade700,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Password Verified',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_isShaking ? _shakeAnimation.value * 0.5 : 0, 0),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.90,
              constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _passwordValidated ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _passwordValidated ? Colors.green.shade200 : Colors.orange.shade200,
                            ),
                          ),
                          child: Icon(
                            _passwordValidated ? Icons.check_circle_outline : Icons.lock_outline,
                            color: _passwordValidated ? Colors.green.shade700 : Colors.orange.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _passwordValidated ? 'Confirm Exit' : 'Exit Protected',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                _passwordValidated
                                    ? 'Password verified, please confirm'
                                    : ExitPasswordService.getPasswordHint(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _passwordValidated ? _cancelConfirmation : _onCancel,
                          icon: const Icon(Icons.close),
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Dynamic content based on state
                    _passwordValidated ? _buildConfirmationSection() : _buildPasswordDisplay(),

                    const SizedBox(height: 20),

                    // Show password input only in password entry state
                    if (!_passwordValidated) ...[
                      // Native Keyboard Input
                      TextField(
                        controller: _passwordController,
                        onChanged: (value) {
                          setState(() {
                            _passwordInput = value;
                            _errorMessage = '';
                          });

                          // Auto-submit when 4 digits are entered
                          if (_passwordInput.length == 4) {
                            _validatePassword();
                          }
                        },
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 8,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '••••',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            letterSpacing: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _errorMessage.isNotEmpty ? Colors.red.shade300 : Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _errorMessage.isNotEmpty ? Colors.red.shade500 : Colors.blue.shade500,
                              width: 2,
                            ),
                          ),
                          errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                        ),
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),

                      const SizedBox(height: 12),
                    ],

                    // Dynamic Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _passwordValidated ? _cancelConfirmation : _onCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              _passwordValidated ? 'No, Go Back' : 'Cancel',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _passwordValidated
                                ? _confirmExit
                                : (_passwordInput.length == 4 ? _validatePassword : null),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _passwordValidated ? Colors.red.shade600 : Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _passwordValidated ? 'Yes, Exit' : 'Enter',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}