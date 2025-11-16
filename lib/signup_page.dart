// lib/signup_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _needsConfirmation = false;

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _showSnack(String text) {
    if (ScaffoldMessenger.maybeOf(context) != null) {
      ScaffoldMessenger.of(context)!.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ---------------- SIGNUP LOGIC ----------------
  Future<void> _doSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    _safeSetState(() {
      _loading = true;
      _error = null;
      _needsConfirmation = false;
    });

    try {
      final res = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      // If Supabase returns session, user is fully signed in
      if (res.session != null) {
        _safeSetState(() {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        });
        return;
      }

      // If no session returned → email confirmation required
      _safeSetState(() => _needsConfirmation = true);
      _showSnack('Sign-up successful. Check your email to confirm (if required).');
    } on AuthException catch (e) {
      _safeSetState(() => _error = e.message);
    } catch (e) {
      debugPrint('Signup error: $e');
      _safeSetState(() => _error = 'Sign-up failed. Please try again.');
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  // ---------------- RESEND CONFIRMATION ----------------
  Future<void> _resendConfirmation() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter a valid email to resend confirmation.');
      return;
    }

    _safeSetState(() => _loading = true);
    try {
      await _supabase.auth.resend(type: OtpType.signup, email: email);
      _showSnack('Confirmation email resent. Please check your inbox.');
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Failed to resend confirmation email.');
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  void _goToLogin() {
    _safeSetState(() {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  // ---------------- UI ----------------
  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 12),
        const FlutterLogo(size: 72),
        const SizedBox(height: 14),
        const Text('Create an account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Sign up to access your dashboard', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.person), labelText: 'Full name'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.email), labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.lock), labelText: 'Password'),
              obscureText: true,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 chars' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline), labelText: 'Confirm password'),
              obscureText: true,
              validator: (v) => (v != _passCtrl.text) ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 14),

            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
            ],

            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _loading ? null : _doSignup,
              child: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create account'),
            ),

            const SizedBox(height: 10),

            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Already have an account?'),
              TextButton(onPressed: _goToLogin, child: const Text('Sign in')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _confirmationBox() {
    if (!_needsConfirmation) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        const Text('Please check your email to confirm your account.', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(onPressed: _goToLogin, child: const Text('Go to Sign in')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _resendConfirmation, child: const Text('Resend email')),
        ])
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Column(
              children: [
                _buildHeader(),
                _buildForm(),
                _confirmationBox(),
                const SizedBox(height: 18),
                const Text(
                  'By creating an account you agree to the Terms of Service',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
