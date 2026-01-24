import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum EmailAuthMode { login, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  bool _isLoading = false;
  EmailAuthMode _emailMode = EmailAuthMode.login;

  // Password visibility toggles
  bool _loginPasswordVisible = false;
  bool _regPasswordVisible = false;
  bool _regConfirmPasswordVisible = false;

  // Email login controllers
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Email registration controllers
  final _registerFormKey = GlobalKey<FormState>();
  final _regFirstNameController = TextEditingController();
  final _regLastNameController = TextEditingController();
  final _regDobController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  DateTime? _selectedDob;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _regFirstNameController.dispose();
    _regLastNameController.dispose();
    _regDobController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _writeUserDocument(
    User user,
    String providerId,
    Map<String, dynamic> extraFields,
  ) async {
    final usersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    // Read existing doc once so we don’t overwrite good data
    final snap = await usersRef.get();
    final exists = snap.exists;
    final existing = snap.data() ?? {};

    String? nonEmptyString(dynamic v) {
      if (v is String) {
        final t = v.trim();
        return t.isEmpty ? null : t;
      }
      return null;
    }

    final incomingName =
        nonEmptyString(user.displayName) ?? nonEmptyString(extraFields['name']);

    // Preserve existing name if incomingName is null
    final finalName = incomingName ?? nonEmptyString(existing['name']);

    final firstName = nonEmptyString(extraFields['firstName']);
    final lastName = nonEmptyString(extraFields['lastName']);
    final dob = nonEmptyString(extraFields['dob']);

    // Build update map carefully (only set fields that are meaningful)
    final Map<String, dynamic> data = {
      'uid': user.uid,
      'email': user.email,
      'photoUrl': user.photoURL,
      'provider': providerId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (finalName != null) data['name'] = finalName;
    if (firstName != null) data['firstName'] = firstName;
    if (lastName != null) data['lastName'] = lastName;
    if (dob != null) data['dob'] = dob;

    // Only set these defaults on first create
    if (!exists) {
      data.addAll({
        'role': 'user',
        'organizerStatus': 'none', // none | pending | approved | rejected
        'isOrganizer': false,
        'savedEventsCount': 0,
        'savedParkingCount': 0,
        'bookingsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await usersRef.set(data, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // GOOGLE SIGN-IN
  // ---------------------------------------------------------------------------
  Future<void> _signInWithGoogle(BuildContext context) async {
    setState(() => _isLoading = true);

    try {
      // Configure Google provider
      final googleProvider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'})
        ..addScope('email');

      UserCredential userCredential;

      if (kIsWeb) {
        // Web: use popup
        userCredential = await FirebaseAuth.instance.signInWithPopup(
          googleProvider,
        );
      } else {
        // Mobile / desktop: use signInWithProvider (no GoogleSignIn plugin needed)
        userCredential = await FirebaseAuth.instance.signInWithProvider(
          googleProvider,
        );
      }

      final user = userCredential.user;
      if (user != null) {
        await _writeUserDocument(user, 'google', {});
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Google sign-in failed');
    } catch (e) {
      _showError('Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // EMAIL REGISTER
  // ---------------------------------------------------------------------------
  Future<void> _registerWithEmail(BuildContext context) async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _regEmailController.text.trim();
      final password = _regPasswordController.text.trim();

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user != null) {
        final firstName = _regFirstNameController.text.trim();
        final lastName = _regLastNameController.text.trim();
        final dob = _regDobController.text.trim();

        await _writeUserDocument(user, 'password', {
          'name': '$firstName $lastName',
          'firstName': firstName,
          'lastName': lastName,
          'dob': dob,
        });

        await user.updateDisplayName('$firstName $lastName');

        // Send verification email once; user stays logged in
        try {
          await user.sendEmailVerification();
        } catch (_) {
          // non-fatal
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification link sent to $email. Please verify from your inbox.',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        // AuthGate will now detect logged-in user and take them to HomeScreen.
      }
    } on FirebaseAuthException catch (e) {
      final msg = e.message ?? 'Registration failed';
      _showError(msg);
    } catch (e) {
      _showError('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // EMAIL LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _loginWithEmail(BuildContext context) async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _loginEmailController.text.trim();
      final password = _loginPasswordController.text.trim();

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Ensure users/{uid} exists for older accounts too
        await _writeUserDocument(user, 'password', {});
      }
      // No emailVerified check here – HomeScreen will block features
      // until the email is actually verified.
    } on FirebaseAuthException catch (e) {
      String msg;
      if (e.code == 'user-not-found') {
        msg = 'No account found for this email.';
      } else if (e.code == 'wrong-password') {
        msg = 'Incorrect password.';
      } else {
        msg = e.message ?? 'Login failed';
      }
      _showError(msg);
    } catch (e) {
      _showError('Login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B6B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORGOT PASSWORD DIALOG
  // ---------------------------------------------------------------------------
  // ⭐ Fixed: Forgot Password Dialog – no manual dispose, safe contexts
  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter your email address and we\'ll send you a link to reset your password.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: Colors.white.withOpacity(0.8),
                            size: 22,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isSending
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: Colors.white.withOpacity(0.2),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSending
                                ? null
                                : () async {
                                    final email = emailController.text.trim();
                                    if (email.isEmpty || !email.contains('@')) {
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            'Please enter a valid email address',
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setDialogState(() => isSending = true);

                                    try {
                                      await FirebaseAuth.instance
                                          .sendPasswordResetEmail(email: email);

                                      if (!dialogContext.mounted) return;

                                      Navigator.of(dialogContext).pop();

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  'Password reset link sent to $email',
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: const Color(
                                            0xFF10B981,
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    } on FirebaseAuthException catch (e) {
                                      if (!dialogContext.mounted) return;

                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.message ??
                                                'Failed to send reset email',
                                          ),
                                          backgroundColor: const Color(
                                            0xFFFF6B6B,
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(() => isSending = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF667EEA),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isSending
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF667EEA),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Send Link',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
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

    // NOTE: no emailController.dispose() here – let the dialog clean up safely.
  }

  // ---------------------------------------------------------------------------
  // DOB PICKER
  // ---------------------------------------------------------------------------
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? initial,
      firstDate: DateTime(1940),
      lastDate: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _regDobController.text =
            '${picked.day.toString().padLeft(2, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.year}';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0), Color(0xFFDA22FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAnimatedLogo(),
                          const SizedBox(height: 40),
                          _buildGlassmorphicCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1000),
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.7 + (value * 0.3),
              child: Transform.rotate(angle: value * 0.1, child: child),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.35),
                  Colors.white.withOpacity(0.1),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                size: 72,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFFFFBEB)],
          ).createShader(bounds),
          child: const Text(
            'Event Discovery',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Find events, parking & food nearby',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.95),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassmorphicCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.25),
                Colors.white.withOpacity(0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAuthModeTabs(),
                const SizedBox(height: 32),
                _buildSocialButtons(),
                const SizedBox(height: 24),
                _buildDivider(),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.1),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _emailMode == EmailAuthMode.login
                      ? _buildEmailLoginForm()
                      : _buildEmailRegisterForm(),
                ),
                const SizedBox(height: 24),
                _buildFeaturesList(),
                const SizedBox(height: 16),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthModeTabs() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              'Sign In',
              EmailAuthMode.login,
              Icons.login_rounded,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              'Sign Up',
              EmailAuthMode.register,
              Icons.person_add_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, EmailAuthMode mode, IconData icon) {
    final isSelected = _emailMode == mode;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: isSelected
            ? const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _emailMode = mode),
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.7),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButtons() {
    return Column(
      children: [
        _buildModernSocialButton(
          onTap: () => _signInWithGoogle(context),
          icon: Icons.g_mobiledata_rounded,
          label: 'Continue with Google',
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        const SizedBox(height: 12),
        _buildModernSocialButton(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Apple Sign-In coming soon!'),
                backgroundColor: Colors.black87,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
          icon: Icons.apple,
          label: 'Continue with Apple',
          gradient: const LinearGradient(
            colors: [Color(0xFF2C3E50), Color(0xFF000000)],
          ),
        ),
      ],
    );
  }

  Widget _buildModernSocialButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Gradient gradient,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _isLoading
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 24, color: Colors.black87),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.white.withOpacity(0.5)],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or continue with email',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.5), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        key: const ValueKey('login'),
        children: [
          _buildModernTextField(
            controller: _loginEmailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildModernTextField(
            controller: _loginPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: !_loginPasswordVisible,
            suffixIcon: IconButton(
              icon: Icon(
                _loginPasswordVisible ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () {
                setState(() => _loginPasswordVisible = !_loginPasswordVisible);
              },
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildModernActionButton(
            label: 'Sign In',
            onPressed: () => _loginWithEmail(context),
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildEmailRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        key: const ValueKey('register'),
        children: [
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  controller: _regFirstNameController,
                  label: 'First Name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernTextField(
                  controller: _regLastNameController,
                  label: 'Last Name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildModernTextField(
            controller: _regDobController,
            label: 'Date of Birth',
            icon: Icons.cake_outlined,
            readOnly: true,
            onTap: _pickDob,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please select your date of birth';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildModernTextField(
            controller: _regEmailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildModernTextField(
            controller: _regPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: !_regPasswordVisible,
            suffixIcon: IconButton(
              icon: Icon(
                _regPasswordVisible ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () {
                setState(() => _regPasswordVisible = !_regPasswordVisible);
              },
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a password';
              }
              if (value.trim().length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildModernTextField(
            controller: _regConfirmPasswordController,
            label: 'Confirm Password',
            icon: Icons.lock_reset_outlined,
            obscureText: !_regConfirmPasswordVisible,
            suffixIcon: IconButton(
              icon: Icon(
                _regConfirmPasswordVisible
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              onPressed: () {
                setState(
                  () =>
                      _regConfirmPasswordVisible = !_regConfirmPasswordVisible,
                );
              },
            ),
            validator: (value) {
              if (value != _regPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildModernActionButton(
            label: 'Create Account',
            onPressed: () => _registerWithEmail(context),
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    VoidCallback? onTap,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withOpacity(0.8),
            size: 22,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          errorStyle: const TextStyle(color: Color(0xFFFECDD3), fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildModernActionButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF0F0F0)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF667EEA),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 20, color: const Color(0xFF667EEA)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildFeatureItem(
            Icons.event_available_rounded,
            'Discover nearby events in minutes',
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            Icons.local_parking_rounded,
            'Find free & paid parking close to venues',
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            Icons.restaurant_rounded,
            'See nearby restaurants, pubs & cafés',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.95),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Text(
      'By continuing, you agree to our Terms & Privacy Policy',
      style: TextStyle(
        fontSize: 11,
        color: Colors.white.withOpacity(0.75),
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  // Optional: old verification dialog (not used now; dashboard popup handles it)
  Widget _buildVerificationDialog(String email) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify Your Email',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We\'ve sent a verification link to:\n\n$email\n\nPlease check your inbox (and spam/junk folder) and click the link to verify your account.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.95),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF667EEA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Got it!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
