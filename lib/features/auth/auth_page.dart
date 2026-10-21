import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreatingAccount = false;
  bool _isBusy = false;
  bool _hidePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isCreatingAccount) {
        final name = _nameController.text.trim();
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = credential.user!;
        await user.updateDisplayName(name);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'displayName': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = _authErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already uses this email. Try signing in instead.';
      case 'invalid-email':
        return 'That email address does not look valid.';
      case 'weak-password':
        return 'Choose a stronger password with at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'network-request-failed':
        return 'Could not connect. Check your internet and try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled in Firebase yet.';
      default:
        return error.message ?? 'Sign-in failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(Icons.code_rounded, color: colors.onPrimary),
                      ),
                      const SizedBox(width: 11),
                      const Text(
                        'KodeKoalesce',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Text(
                    _isCreatingAccount ? 'Join the community' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isCreatingAccount
                        ? 'Create an account to find your people and build together.'
                        : 'Sign in to pick up where you left off.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 25),
                  Card(
                    elevation: 0,
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isCreatingAccount) ...[
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Your name',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) => value == null || value.trim().isEmpty
                                    ? 'Enter your name'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                return email.contains('@') && email.contains('.')
                                    ? null
                                    : 'Enter a valid email address';
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _hidePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _isBusy ? null : _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.length < 6) {
                                  return 'Use at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: colors.error, height: 1.35),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _isBusy ? null : _submit,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isBusy
                                  ? SizedBox(
                                      width: 21,
                                      height: 21,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.onPrimary,
                                      ),
                                    )
                                  : Text(_isCreatingAccount ? 'Create account' : 'Sign in'),
                            ),
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: _isBusy
                                  ? null
                                  : () => setState(() {
                                      _isCreatingAccount = !_isCreatingAccount;
                                      _errorMessage = null;
                                    }),
                              child: Text(
                                _isCreatingAccount
                                    ? 'Already have an account? Sign in'
                                    : 'New here? Create an account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'A community for the people behind the code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: mutedText(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
