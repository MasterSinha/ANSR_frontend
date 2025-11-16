// lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseClient _supabase = Supabase.instance.client;

  // controllers
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // helper: show snack
  void _showSnack(String msg) {
    if (ScaffoldMessenger.maybeOf(context) != null) {
      ScaffoldMessenger.of(context)!.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---------- Sign-in ----------
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _supabase.auth.signInWithPassword(email: email, password: password);

      if (res.session != null) {
        // success: navigate to Home (replace root)
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      } else {
        // session null could mean email confirmation needed (if enabled)
        _showSnack('Check your email to confirm sign-in (if required).');
      }
    } on AuthException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------- Navigate to Sign-up ----------
  void _goToSignup() {
    Navigator.pushNamed(context, '/signup');
  }

  // ---------- Password reset ----------
  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final key = GlobalKey<FormState>();
        return AlertDialog(
          title: const Text('Reset password'),
          content: Form(
            key: key,
            child: TextFormField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (!key.currentState!.validate()) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Send'),
            )
          ],
        );
      },
    );

    if (res != true) return;
    final email = ctrl.text.trim();
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      _showSnack('Password reset email sent (check your inbox).');
    } on AuthException catch (err) {
      _showSnack(err.message);
    } catch (e) {
      _showSnack('Failed to send reset email.');
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in'), elevation: 0),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 28),
            child: Column(
              children: [
                const FlutterLogo(size: 72),
                const SizedBox(height: 18),
                const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Sign in to continue', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),

                Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 6) ? 'Password min 6 chars' : null,
                    ),
                    const SizedBox(height: 12),

                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _loading ? null : _signIn,
                            child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      TextButton(onPressed: _loading ? null : _goToSignup, child: const Text('Create account')),
                      TextButton(onPressed: _loading ? null : _forgotPassword, child: const Text('Forgot password?')),
                    ]),

                    const SizedBox(height: 12),

                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Or sign in with', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),

                    // Example social sign-in button (Google provider requires setup in Supabase and platform)
                    ElevatedButton.icon(
                      onPressed: () async {
                        _showSnack('Social sign-in requires configuring provider in Supabase and platform. See Supabase docs.');
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google (placeholder)'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    )
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
