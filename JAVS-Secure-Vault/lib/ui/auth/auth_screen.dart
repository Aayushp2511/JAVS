import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/cyber_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  List<String> _previousEmails = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final savedEmail = await _storage.read(key: 'saved_email');
    final savedPassword = await _storage.read(key: 'saved_password');
    final rememberMe = await _storage.read(key: 'remember_me');
    
    if (rememberMe == 'true' && savedEmail != null) {
      setState(() {
        _rememberMe = true;
        _emailController.text = savedEmail;
        if (savedPassword != null) {
          _passwordController.text = savedPassword;
        }
      });
    }
    
    await _loadPreviousEmails();
  }

  Future<void> _loadPreviousEmails() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      
      setState(() {
        _previousEmails = snapshot.docs
            .map((doc) => doc['email'] as String)
            .toList();
      });
    } catch (e) {
      print('Error loading previous emails: $e');
    }
  }

  Future<void> _saveCredentials() async {
    if (_rememberMe) {
      await _storage.write(key: 'saved_email', value: _emailController.text.trim());
      await _storage.write(key: 'saved_password', value: _passwordController.text.trim());
      await _storage.write(key: 'remember_me', value: 'true');
    } else {
      await _storage.delete(key: 'saved_email');
      await _storage.delete(key: 'saved_password');
      await _storage.write(key: 'remember_me', value: 'false');
    }
  }

  Future<void> _submit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await _saveCredentials();
      } else {
        if (_nameController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter your name')),
          );
          return;
        }
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'displayName': _nameController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
          'status': 'Online',
          'lastUpdate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        await _saveCredentials();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: CyberTheme.errorNeon,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 80, color: CyberTheme.primaryNeon),
                const SizedBox(height: 16),
                Text(
                  'JAVS Secure Vault',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Sign in to continue' : 'Create your account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 40),
                
                if (!_isLogin)
                  _buildField('Full Name', _nameController, Icons.person_outline),
                
                if (!_isLogin) const SizedBox(height: 16),
                
                _buildEmailField(),
                
                const SizedBox(height: 16),
                _buildField('Password', _passwordController, Icons.lock_outline, obscure: true),
                
                if (_isLogin) const SizedBox(height: 8),
                
                if (_isLogin)
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() => _rememberMe = value ?? false);
                        },
                        activeColor: CyberTheme.primaryNeon,
                      ),
                      const Text('Remember me'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          if (_emailController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter your email first')),
                            );
                            return;
                          }
                          await FirebaseAuth.instance.sendPasswordResetEmail(
                            email: _emailController.text.trim(),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password reset email sent')),
                          );
                        },
                        child: const Text('Forgot Password?'),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 24),
                
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: CyberTheme.primaryNeon))
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CyberTheme.primaryNeon,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isLogin ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin ? "Don't have an account? " : 'Already have an account? ',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin ? 'Sign Up' : 'Sign In',
                        style: const TextStyle(
                          color: CyberTheme.primaryNeon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField('Email', _emailController, Icons.email_outlined),
        if (_isLogin && _previousEmails.isNotEmpty) ...
          [
            const SizedBox(height: 8),
            const Text(
              'Recent emails:',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _previousEmails.map((email) {
                return ActionChip(
                  label: Text(
                    email,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    setState(() => _emailController.text = email);
                  },
                  backgroundColor: CyberTheme.surface,
                );
              }).toList(),
            ),
          ],
      ],
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {bool obscure = false}) {
    return Container(
      decoration: BoxDecoration(
        color: CyberTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: CyberTheme.primaryNeon.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
