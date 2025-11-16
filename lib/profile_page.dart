// lib/profile_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ProfilePage extends StatefulWidget {
  /// Optional callback to notify the app that theme changed (true == dark).
  final void Function(bool isDark)? onThemeChanged;

  const ProfilePage({super.key, this.onThemeChanged});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // profile fields
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String _avatarUrl = '';
  bool _notificationsEnabled = true;
  String _language = 'English';
  bool _isDark = false;

  // whether the user is logged in
  User? _user;

  final DateFormat _dateFormat = DateFormat.yMMMMd();

  @override
  void initState() {
    super.initState();
    _loadPrefsAndProfile();
  }

  Future<void> _loadPrefsAndProfile() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool('pref_notifications') ?? true;
      _language = prefs.getString('pref_language') ?? 'English';
      _isDark = prefs.getBool('pref_theme_dark') ?? false;

      // load current user from Supabase
      final current = supabase.auth.currentUser;
      _user = current;

      if (current != null) {
        _email = current.email ?? '';

        // attempt to load profile row from `profiles` table (common Supabase pattern)
        // we use try/catch and tolerant parsing to avoid SDK-specific method issues
        final resp = await supabase.from('profiles').select().eq('id', current.id).limit(1);
        if (resp is List && resp.isNotEmpty) {
          final resMap = resp.first;
          if (resMap is Map<String, dynamic>) {
            _fullName = (resMap['full_name'] ?? '').toString();
            _phone = (resMap['phone'] ?? '').toString();
            _avatarUrl = (resMap['avatar_url'] ?? '').toString();
          }
        }
      }

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('Error loading profile: $e\n$st');
      setState(() {
        _loading = false;
        _error = 'Failed to load profile';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) {
      _showSnack('No authenticated user', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = {
        'id': _user!.id,
        'full_name': _fullName,
        'phone': _phone,
        'avatar_url': _avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // In this SDK version, do not call .execute(); just await the chain.
      await supabase.from('profiles').upsert(payload);

      _showSnack('Profile saved');
    } catch (e) {
      debugPrint('Save profile error: $e');
      _showSnack('Failed to save profile', isError: true);
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_email.isEmpty) {
      _showSnack('No email available', isError: true);
      return;
    }
    try {
      // resetPasswordForEmail returns void in many SDK versions — just await it
      await supabase.auth.resetPasswordForEmail(_email);
      _showSnack('Password reset email sent to $_email');
    } catch (e) {
      debugPrint('Password reset error: $e');
      _showSnack('Failed to send reset email', isError: true);
    }
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      _showSnack('Logged out');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      debugPrint('Logout error: $e');
      _showSnack('Logout failed', isError: true);
    }
  }

  Future<void> _deleteProfileRowAndSignOut() async {
    final ok = await _confirmDialog('Delete account', 'This will remove your profile data from the database. It will NOT delete the authentication user (server-side). Are you sure?');
    if (!ok) return;

    setState(() => _loading = true);
    try {
      if (_user != null) {
        // do not call .execute(); await the filter builder directly
        await supabase.from('profiles').delete().eq('id', _user!.id);
      }
      await supabase.auth.signOut();
      _showSnack('Profile removed and signed out');
    } catch (e) {
      debugPrint('Delete profile error: $e');
      _showSnack('Delete failed', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_notifications', value);
    setState(() => _notificationsEnabled = value);
    _showSnack(value ? 'Notifications enabled' : 'Notifications disabled');
  }

  Future<void> _setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_language', lang);
    setState(() => _language = lang);
    _showSnack('Language set to $lang');
  }

  Future<void> _setTheme(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_theme_dark', dark);
    setState(() => _isDark = dark);
    widget.onThemeChanged?.call(dark);
    _showSnack('Theme updated');
  }

  Future<bool> _confirmDialog(String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Proceed')),
        ],
      ),
    );
    return res == true;
  }

  void _showSnack(String text, {bool isError = false}) {
    final sc = ScaffoldMessenger.of(context);
    sc.clearSnackBars();
    sc.showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? Colors.red : null));
  }

  // UI helpers
  Widget _avatarCircle() {
    final avatar = _avatarUrl.trim().isEmpty ? null : NetworkImage(_avatarUrl);
    return CircleAvatar(
      radius: 52,
      backgroundColor: Colors.grey[200],
      foregroundImage: avatar,
      child: avatar == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
    );
  }

  // show edit dialog
  Future<void> _showEditDialog() async {
    final nameController = TextEditingController(text: _fullName);
    final phoneController = TextEditingController(text: _phone);
    final avatarController = TextEditingController(text: _avatarUrl);

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 8),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                TextField(controller: avatarController, decoration: const InputDecoration(labelText: 'Avatar URL (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _fullName = nameController.text.trim();
                  _phone = phoneController.text.trim();
                  _avatarUrl = avatarController.text.trim();
                });
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true) await _saveProfile();
  }

  // show language chooser
  Future<void> _showLanguageDialog() async {
    final langs = ['English', 'हिन्दी', 'Español', 'Français'];
    final pick = await showDialog<String>(
      context: context,
      builder: (_) {
        return SimpleDialog(
          title: const Text('Choose language'),
          children: langs
              .map((l) => SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(l),
            child: Text(l),
          ))
              .toList(),
        );
      },
    );
    if (pick != null) await _setLanguage(pick);
  }

  // show change password confirmation (send reset email)
  Future<void> _showChangePasswordDialog() async {
    final ok = await _confirmDialog('Change password', 'We will send a password reset link to $_email. Continue?');
    if (!ok) return;
    await _sendPasswordReset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadPrefsAndProfile,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Center(child: _avatarCircle()),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _fullName.isEmpty ? 'Guest User' : _fullName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text(_email.isEmpty ? 'Not signed in' : _email, style: const TextStyle(color: Colors.black54))),
            const SizedBox(height: 16),

            // Account card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit profile'),
                    subtitle: const Text('Change name, phone, avatar'),
                    onTap: _showEditDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: const Text('Change password'),
                    subtitle: Text(_email.isEmpty ? 'Sign in to enable' : 'Send reset link to $_email'),
                    onTap: _email.isEmpty ? null : _showChangePasswordDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
                    subtitle: const Text('Sign out from this device'),
                    onTap: _logout,
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Preferences card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
              child: Column(
                children: [
                  SwitchListTile(
                    value: _notificationsEnabled,
                    onChanged: (v) => _setNotifications(v),
                    secondary: const Icon(Icons.notifications),
                    title: const Text('Notifications'),
                    subtitle: const Text('Enable push / in-app notifications'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: const Text('Language'),
                    subtitle: Text(_language),
                    onTap: _showLanguageDialog,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _isDark,
                    onChanged: (v) => _setTheme(v),
                    secondary: const Icon(Icons.brightness_6),
                    title: const Text('Dark theme'),
                    subtitle: const Text('Toggle app theme'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // App info
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('App version'),
                    subtitle: const Text('1.0.0'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy & Terms'),
                    subtitle: const Text('View privacy policy and terms'),
                    onTap: () {
                      // open a link or page
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Danger zone
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.red[50],
              elevation: 0,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Delete profile', style: TextStyle(color: Colors.red)),
                    subtitle: const Text('Remove your profile data (local & DB).'),
                    onTap: _deleteProfileRowAndSignOut,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
