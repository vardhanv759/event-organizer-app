import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Notification toggles
  bool _pushNotifications = true;
  bool _eventReminders = true;
  bool _parkingUpdates = true;

  // Preferences
  String _theme = 'system'; // light, dark, system

  // App info
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadAppInfo();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications = prefs.getBool('pushNotifications') ?? true;
      _eventReminders = prefs.getBool('eventReminders') ?? true;
      _parkingUpdates = prefs.getBool('parkingUpdates') ?? true;
      _theme = prefs.getString('theme') ?? 'system';
    });
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _loadAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _changePassword() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Check if user signed in with email/password
    final providerData = currentUser.providerData;
    final hasPasswordProvider = providerData.any(
      (info) => info.providerId == 'password',
    );

    if (!hasPasswordProvider) {
      _showMessage(
        'You signed in with ${providerData.first.providerId}. Password change not available.',
        isError: true,
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );

    if (result == true && mounted) {
      _showMessage('Password changed successfully');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.\n\n'
          'All your data including saved events, restaurants, and bookings will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          // Delete user data from Firestore
          await _db.collection('users').doc(uid).delete();

          // Delete Firebase Auth account
          await _auth.currentUser?.delete();

          if (mounted) {
            // Navigate to login screen
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        }
      } catch (e) {
        if (mounted) {
          _showMessage('Failed to delete account: $e', isError: true);
        }
      }
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showMessage('Failed to open link', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FF),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ACCOUNT SECTION
          _buildSectionHeader('ACCOUNT'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: Icons.lock_rounded,
                title: 'Change Password',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
                onTap: _changePassword,
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                icon: Icons.delete_rounded,
                title: 'Delete Account',
                titleColor: const Color(0xFFEF4444),
                iconColor: const Color(0xFFEF4444),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFEF4444),
                ),
                onTap: _deleteAccount,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // NOTIFICATIONS SECTION
          _buildSectionHeader('NOTIFICATIONS'),
          _buildSettingsCard(
            children: [
              _buildSwitchTile(
                icon: Icons.notifications_rounded,
                title: 'Push Notifications',
                value: _pushNotifications,
                onChanged: (value) {
                  setState(() => _pushNotifications = value);
                  _savePreference('pushNotifications', value);
                },
              ),
              const Divider(height: 1),
              _buildSwitchTile(
                icon: Icons.event_rounded,
                title: 'Event Reminders',
                subtitle: 'Get notified about upcoming events',
                value: _eventReminders,
                onChanged: (value) {
                  setState(() => _eventReminders = value);
                  _savePreference('eventReminders', value);
                },
              ),
              const Divider(height: 1),
              _buildSwitchTile(
                icon: Icons.local_parking_rounded,
                title: 'Parking Updates',
                subtitle: 'Booking confirmations and reminders',
                value: _parkingUpdates,
                onChanged: (value) {
                  setState(() => _parkingUpdates = value);
                  _savePreference('parkingUpdates', value);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // PREFERENCES SECTION
          _buildSectionHeader('PREFERENCES'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: Icons.palette_rounded,
                title: 'Theme',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _theme == 'light'
                          ? 'Light'
                          : _theme == 'dark'
                          ? 'Dark'
                          : 'System',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
                onTap: () => _showThemeSelector(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ABOUT SECTION
          _buildSectionHeader('ABOUT'),
          _buildSettingsCard(
            children: [
              _buildSettingsTile(
                icon: Icons.info_rounded,
                title: 'Version',
                trailing: Text(
                  _appVersion,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy Policy',
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  color: Color(0xFF94A3B8),
                ),
                onTap: () => _openUrl('https://yourwebsite.com/privacy'),
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                icon: Icons.description_rounded,
                title: 'Terms of Service',
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  color: Color(0xFF94A3B8),
                ),
                onTap: () => _openUrl('https://yourwebsite.com/terms'),
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                icon: Icons.help_rounded,
                title: 'Help & Support',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
                onTap: () {
                  // Navigate to Help & Support screen
                  // Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen()));
                  _showMessage('Help & Support screen - Coming soon!');
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? const Color(0xFF7C3AED)).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? const Color(0xFF7C3AED),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: titleColor ?? const Color(0xFF0F172A),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF7C3AED), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF7C3AED),
      ),
    );
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildSelector(
        title: 'Theme',
        options: const ['Light', 'Dark', 'System'],
        values: const ['light', 'dark', 'system'],
        currentValue: _theme,
        onSelected: (value) {
          setState(() => _theme = value);
          _savePreference('theme', value);

          // ✅ UPDATE: Notify the app to change theme
          Provider.of<ThemeProvider>(context, listen: false).setTheme(value);
        },
      ),
    );
  }

  Widget _buildSelector({
    required String title,
    required List<String> options,
    required List<String> values,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(options.length, (index) {
            final value = values[index];
            final isSelected = value == currentValue;
            return ListTile(
              title: Text(
                options[index],
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF0F172A),
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_rounded, color: Color(0xFF7C3AED))
                  : null,
              onTap: () {
                onSelected(value);
                Navigator.pop(context);
              },
            );
          }),
        ],
      ),
    );
  }
}

// Change Password Dialog
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    if (newPassword != confirm) {
      _showError('New passwords do not match');
      return;
    }

    if (newPassword.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final email = user.email!;

      // Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: email,
        password: current,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Failed to change password');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPasswordController,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newPasswordController,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _changePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change'),
        ),
      ],
    );
  }
}
