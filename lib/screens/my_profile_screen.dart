import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Standard "good enough" UK postcode pattern (covers all current
/// postcode area formats: A9 9AA, A99 9AA, AA9 9AA, AA99 9AA, A9A 9AA,
/// AA9A 9AA). Deliberately permissive rather than validating against a
/// real postcode database - this catches typos/garbage input, not
/// "does this postcode actually exist."
final RegExp _ukPostcodeRegExp = RegExp(r'^[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}$');

/// Returns null (valid) if empty - postcode is an optional field - or a
/// validation error message otherwise.
String? _validateUkPostcode(String? value) {
  final v = (value ?? '').trim().toUpperCase();
  if (v.isEmpty) return null;
  if (!_ukPostcodeRegExp.hasMatch(v)) {
    return 'Enter a valid UK postcode (e.g. HA9 0WS)';
  }
  return null;
}

/// UK vehicle registration plates have used several formats over the
/// decades (current, prefix, suffix, and dateless), so this checks
/// against all of them rather than just the current 2001-onward format -
/// otherwise older or cherished plates would be wrongly rejected.
final List<RegExp> _ukPlateFormats = [
  RegExp(r'^[A-Z]{2}\d{2}[A-Z]{3}$'), // current: AB12 CDE
  RegExp(r'^[A-Z]\d{1,3}[A-Z]{3}$'), // prefix: A123 BCD
  RegExp(r'^[A-Z]{3}\d{1,3}[A-Z]$'), // suffix: ABC 123D
  RegExp(r'^[A-Z]{1,3}\d{1,4}$'), // dateless: A 1, ABC 123
  RegExp(r'^\d{1,4}[A-Z]{1,3}$'), // dateless: 1 A, 123 ABC
];

/// Returns null (valid) if empty - vehicle reg is an optional field - or
/// a validation error message otherwise.
String? _validateUkPlate(String? value) {
  final v = (value ?? '').trim().toUpperCase().replaceAll(' ', '');
  if (v.isEmpty) return null;
  if (v.length < 2 || v.length > 7) {
    return 'Enter a valid vehicle registration';
  }
  final matches = _ukPlateFormats.any((re) => re.hasMatch(v));
  if (!matches) {
    return 'Enter a valid vehicle registration (e.g. AB12 CDE)';
  }
  return null;
}

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _deleting = false;

  String? _photoUrl; // from Firestore/Auth
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleCtrl.dispose();
    _postcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      _email = user.email;

      // Try Firestore first
      final docRef = _db.collection('users').doc(user.uid);
      final snap = await docRef.get();

      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        // 'name' is the canonical field written by login_screen.dart and
        // read by the entire messaging system (ChatAvatar, ChatUserName,
        // the parking Host card, etc). This used to read 'displayName' -
        // a field this screen was the only place that ever wrote, which
        // meant editing your name here silently desynced from what every
        // chat/listing showed, since those all read 'name' instead.
        _nameCtrl.text = (data['name'] ?? user.displayName ?? '').toString();
        _phoneCtrl.text = (data['phone'] ?? '').toString();
        _vehicleCtrl.text = (data['vehicleReg'] ?? '').toString();
        _postcodeCtrl.text = (data['homePostcode'] ?? '').toString();
        _photoUrl = (data['photoUrl'] ?? user.photoURL)?.toString();
      } else {
        // Create a baseline doc (optional but recommended)
        _nameCtrl.text = user.displayName ?? '';
        _photoUrl = user.photoURL;

        await docRef.set({
          'name': _nameCtrl.text.trim(),
          'email': user.email,
          'photoUrl': _photoUrl,
          'phone': '',
          'vehicleReg': '',
          'homePostcode': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Keep UI stable even if Firestore read fails
      final user = _auth.currentUser;
      _nameCtrl.text = user?.displayName ?? '';
      _photoUrl = user?.photoURL;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final displayName = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final vehicleReg = _vehicleCtrl.text.trim().toUpperCase();
    final homePostcode = _postcodeCtrl.text.trim().toUpperCase();

    try {
      // Update Firestore
      await _db.collection('users').doc(user.uid).set({
        'name': displayName,
        'email': user.email,
        'photoUrl': _photoUrl,
        'phone': phone,
        'vehicleReg': vehicleReg,
        'homePostcode': homePostcode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update Auth profile too (nice for global usage)
      await user.updateDisplayName(displayName);

      // Force photoURL update to trigger StreamBuilder refresh
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        await user.updatePhotoURL(_photoUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Profile updated successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------
  // ACCOUNT DELETION (GDPR)
  // ---------------------------------------------------------------------
  //
  // What this does:
  //  1. Anonymizes the Firestore profile (clears name/photo/phone/vehicle/
  //     postcode/email, sets account_deleted + deletedAt). It does NOT
  //     delete the `users/{uid}` document outright - the security rules
  //     correctly forbid that (`allow delete: if false`), and even if
  //     they allowed it, deleting the doc would leave every chat message,
  //     parking listing, and review that references this uid pointing at
  //     nothing. Anonymizing satisfies GDPR's "erasure of personal data"
  //     requirement while keeping the rest of the app's data intact.
  //  2. Deletes their avatar from Storage.
  //  3. Deletes the actual Firebase Auth account, so they can no longer
  //     sign back in.
  //
  // What this does NOT do, and would need a Cloud Function (Admin SDK)
  // to do properly: cascade-clean their parking_spaces listings, chat
  // messages, or reviews subcollection. The client can't safely do that
  // here - it would mean either granting broad delete permissions that
  // weaken the security rules for everyone, or silently leaving a
  // provider's live listings active after they've "deleted" their
  // account. Flagging this clearly rather than overstating what a
  // client-only deletion can actually guarantee.
  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirmed = await _showDeleteConfirmationDialog();
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _deleting = true);

    try {
      await _performAccountDeletion(user);
      // Success - FirebaseAuth's authStateChanges() will fire elsewhere
      // in the app (e.g. an AuthGate) and take the user back to the
      // login screen automatically once the Auth account is gone.
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        final reauthed = await _reauthenticate(user);
        if (reauthed && mounted) {
          try {
            await _performAccountDeletion(user);
          } catch (e2) {
            _showDeleteError('$e2');
          }
        }
      } else {
        _showDeleteError(e.message ?? 'Failed to delete account');
      }
    } catch (e) {
      _showDeleteError('$e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _performAccountDeletion(User user) async {
    final uid = user.uid;

    try {
      await _db.collection('users').doc(uid).set({
        'name': 'Deleted User',
        'phone': '',
        'vehicleReg': '',
        'homePostcode': '',
        'photoUrl': null,
        'email': null,
        'account_deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: even if the anonymization write fails (e.g. offline),
      // still proceed to delete the Auth account below - the person
      // explicitly asked to delete their account, and leaving them
      // stuck mid-flow, still able to log back in, would be worse than
      // a profile doc that didn't get fully scrubbed.
    }

    if (_photoUrl != null &&
        _photoUrl!.isNotEmpty &&
        _photoUrl!.contains('user_profiles%2F')) {
      try {
        await _storage.refFromURL(_photoUrl!).delete();
      } catch (_) {
        // Non-fatal - see _pickAndUploadPhoto for the same pattern.
      }
    }

    await user.delete();
  }

  Future<bool> _reauthenticate(User user) async {
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) {
      return _reauthenticateWithGoogle(user);
    }
    return _reauthenticateWithPassword(user);
  }

  Future<bool> _reauthenticateWithGoogle(User user) async {
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
      return true;
    } catch (e) {
      _showDeleteError('Re-authentication failed: $e');
      return false;
    }
  }

  Future<bool> _reauthenticateWithPassword(User user) async {
    final passwordController = TextEditingController();
    bool obscure = true;
    bool submitting = false;
    String? errorText;
    bool result = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Confirm your password',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'For your security, please re-enter your password for '
                    '${user.email ?? 'your account'} to continue.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscure,
                    autofocus: true,
                    enabled: !submitting,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: errorText,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          size: 20,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final password = passwordController.text;
                          if (password.isEmpty) {
                            setDialogState(
                              () => errorText = 'Please enter your password',
                            );
                            return;
                          }
                          setDialogState(() {
                            submitting = true;
                            errorText = null;
                          });
                          try {
                            final cred = EmailAuthProvider.credential(
                              email: user.email ?? '',
                              password: password,
                            );
                            await user.reauthenticateWithCredential(cred);
                            result = true;
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() {
                              submitting = false;
                              errorText =
                                  e.code == 'wrong-password' ||
                                      e.code == 'invalid-credential'
                                  ? 'Incorrect password'
                                  : (e.message ?? 'Re-authentication failed');
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.dispose();
    return result;
  }

  Future<bool?> _showDeleteConfirmationDialog() async {
    final confirmController = TextEditingController();
    bool canConfirm = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_rounded, color: Color(0xFFEF4444)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete account',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes your account and signs you '
                    'out. This cannot be undone.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your name, photo, phone number, and vehicle details '
                    'will be removed. Past messages or listings may still '
                    'reference your account as "Deleted User".',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Type DELETE to confirm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    textCapitalization: TextCapitalization.characters,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'DELETE',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setDialogState(
                      () => canConfirm = v.trim().toUpperCase() == 'DELETE',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canConfirm
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                  child: const Text('Delete forever'),
                ),
              ],
            );
          },
        );
      },
    );

    confirmController.dispose();
    return result;
  }

  void _showDeleteError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Couldn\'t delete account: $message'),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (file == null) return;

      setState(() => _uploadingPhoto = true);

      // Capture the outgoing photo before it's replaced, so it can be
      // cleaned up from Storage once the new one is confirmed uploaded.
      final previousPhotoUrl = _photoUrl;

      final Uint8List bytes = await file.readAsBytes();

      // Add timestamp to filename to bust cache
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child(
        'user_profiles/${user.uid}/avatar_$timestamp.jpg',
      );

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uid': user.uid},
        cacheControl: 'public, max-age=300', // Cache for 5 minutes
      );

      await ref.putData(bytes, metadata);
      final url = await ref.getDownloadURL();

      // Save URL in Firestore + Auth
      await _db.collection('users').doc(user.uid).set({
        'photoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await user.updatePhotoURL(url);

      // Best-effort cleanup of the old avatar now that the new one is
      // live everywhere it needs to be. Every previous upload used to be
      // left behind in Storage forever - this only deletes files this
      // app itself uploaded (under user_profiles/), never a bare Google
      // photo URL, and a failure here (e.g. already deleted, permission
      // quirk) is swallowed since it must never block the profile update
      // the user is actually waiting on.
      if (previousPhotoUrl != null &&
          previousPhotoUrl.isNotEmpty &&
          previousPhotoUrl != url &&
          previousPhotoUrl.contains('user_profiles%2F')) {
        try {
          await _storage.refFromURL(previousPhotoUrl).delete();
        } catch (_) {
          // Non-fatal - orphaning one file is far better than blocking
          // or failing the photo update the user just performed.
        }
      }

      if (mounted) {
        setState(() => _photoUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Profile photo updated!'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Choose photo source',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                _PhotoOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 12),
                _PhotoOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from Gallery',
                  color: const Color(0xFF06B6D4),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  int _calculateProfileCompletion() {
    int filled = 0;
    int total = 5;

    if (_nameCtrl.text.trim().isNotEmpty) filled++;
    if (_photoUrl != null && _photoUrl!.isNotEmpty) filled++;
    if (_phoneCtrl.text.trim().isNotEmpty) filled++;
    if (_vehicleCtrl.text.trim().isNotEmpty) filled++;
    if (_postcodeCtrl.text.trim().isNotEmpty) filled++;

    return ((filled / total) * 100).round();
  }

  Widget _buildHeader() {
    final completion = _calculateProfileCompletion();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF6D28D9), Color(0xFF5B21B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: (_saving || _loading) ? null : _saveProfile,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7C3AED),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Avatar and stats
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                children: [
                  // Large avatar
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.white,
                          backgroundImage:
                              (_photoUrl != null && _photoUrl!.isNotEmpty)
                              ? NetworkImage(
                                  '$_photoUrl?v=${_photoUrl.hashCode}',
                                )
                              : null,
                          child: (_photoUrl == null || _photoUrl!.isEmpty)
                              ? const Icon(
                                  Icons.person_rounded,
                                  size: 60,
                                  color: Color(0xFF7C3AED),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 4,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploadingPhoto ? null : _showPhotoOptions,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              child: _uploadingPhoto
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Color(0xFF7C3AED),
                                            ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 20,
                                      color: Color(0xFF7C3AED),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name and email
                  Text(
                    _nameCtrl.text.isEmpty ? 'Your Name' : _nameCtrl.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _email ?? '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Profile completion
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Profile Completion',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$completion%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: completion / 100,
                            minHeight: 8,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF7C3AED),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FF),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          const Text(
                            'Personal Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Form
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _EnhancedTextField(
                                  controller: _nameCtrl,
                                  label: 'Full Name',
                                  hint: 'e.g., John Smith',
                                  icon: Icons.badge_outlined,
                                  validator: (v) {
                                    final s = (v ?? '').trim();
                                    if (s.isEmpty) {
                                      return 'Name cannot be empty';
                                    }
                                    if (s.length < 2) {
                                      return 'Enter a valid name';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 16),

                                _EnhancedTextField(
                                  initialValue: _email ?? '',
                                  label: 'Email',
                                  icon: Icons.alternate_email_outlined,
                                  enabled: false,
                                ),

                                const SizedBox(height: 16),

                                _EnhancedTextField(
                                  controller: _phoneCtrl,
                                  label: 'Phone Number',
                                  hint: 'e.g., +44 7xxx xxxxxx',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),

                                const SizedBox(height: 16),

                                _EnhancedTextField(
                                  controller: _vehicleCtrl,
                                  label: 'Vehicle Registration',
                                  hint: 'e.g., AB12 CDE',
                                  icon: Icons.directions_car_outlined,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: _validateUkPlate,
                                ),

                                const SizedBox(height: 16),

                                _EnhancedTextField(
                                  controller: _postcodeCtrl,
                                  label: 'Home Postcode',
                                  hint: 'e.g., HA9 0WS',
                                  icon: Icons.home_outlined,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: _validateUkPostcode,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Info card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF7C3AED).withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF7C3AED,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFF7C3AED),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Complete your profile to unlock personalized recommendations and faster bookings.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Danger zone
                          const Text(
                            'Danger Zone',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEF4444),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Deleting your account is permanent. Your '
                                  'personal details will be removed and you '
                                  'will be signed out immediately.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7F1D1D),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _deleting
                                        ? null
                                        : _deleteAccount,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFEF4444),
                                      side: const BorderSide(
                                        color: Color(0xFFEF4444),
                                        width: 1.4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: _deleting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Color(0xFFEF4444),
                                                  ),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_forever_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      _deleting
                                          ? 'Deleting…'
                                          : 'Delete My Account',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Enhanced text field widget
class _EnhancedTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _EnhancedTextField({
    this.controller,
    this.initialValue,
    required this.label,
    this.hint,
    required this.icon,
    this.enabled = true,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),
          TextFormField(
            controller: controller,
            initialValue: initialValue,
            enabled: enabled,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            validator: validator,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: const Color(0xFF94A3B8).withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(
                icon,
                color: enabled
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF94A3B8),
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              errorStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Photo option widget
class _PhotoOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PhotoOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
