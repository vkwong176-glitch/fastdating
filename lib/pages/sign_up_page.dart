import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../widgets/pressable_opacity.dart';
import '../providers/auth_provider.dart';

/// 註冊頁（對齊右圖）：簡潔表單、無頂部圖、Login Name、Email、Phone、Password、Confirm Password
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _loginNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pwdController = TextEditingController();
  final _confirmPwdController = TextEditingController();
  bool _obscurePwd = true;
  bool _obscureConfirmPwd = true;

  @override
  void dispose() {
    _loginNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pwdController.dispose();
    _confirmPwdController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_loginNameController.text.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login Name 至少 4 個字元')),
      );
      return;
    }
    if (_emailController.text.isEmpty || _pwdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 Email 與密碼')),
      );
      return;
    }
    if (_pwdController.text != _confirmPwdController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('兩次密碼輸入不一致')),
      );
      return;
    }
    try {
      final err = await Provider.of<AuthProvider>(context, listen: false)
          .registerWithEmailPassword(
        email: _emailController.text.trim(),
        password: _pwdController.text,
        loginName: _loginNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        return;
      }
      context.go('/main');
    } catch (e, st) {
      debugPrint('Sign up failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('註冊失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = ResponsiveLayout.isWide(context);
    final maxW = isWide ? 420.0 : size.width;
    final horizontalPadding = isWide ? 32.0 : 24.0;

    return Scaffold(
      backgroundColor: AppConstants.loginFormBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBilingualTitle(),
                    const SizedBox(height: 4),
                    _buildBilingualSubtitle(),
                    const SizedBox(height: 14),
                    _buildBilingualLabel(
                      'Login Name : (At least 4 characters)',
                      '登入名稱（至少 4 個字元）',
                    ),
                    const SizedBox(height: 3),
                    _buildLoginNameField(),
                    const SizedBox(height: 8),
                    _buildBilingualLabel('Email', '電子郵件'),
                    const SizedBox(height: 3),
                    _buildEmailField(),
                    const SizedBox(height: 8),
                    _buildBilingualLabel(
                      'Phone : country code + number',
                      '電話（國碼＋號碼）',
                    ),
                    const SizedBox(height: 3),
                    _buildPhoneField(),
                    const SizedBox(height: 8),
                    _buildBilingualLabel('Password', '密碼'),
                    const SizedBox(height: 3),
                    _buildPasswordField(),
                    const SizedBox(height: 8),
                    _buildBilingualLabel('Confirm Password', '確認密碼'),
                    const SizedBox(height: 3),
                    _buildConfirmPasswordField(),
                    const SizedBox(height: 14),
                    PressableOpacity(
                      onPressed: _signUp,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppConstants.loginButtonPurple,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: const [
                              Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                '註冊',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Text(
                            'Already have an account?',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '已有帳戶？',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.signUpLinkBlue,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Sign In here · 前往登入',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                                color: AppConstants.signUpLinkBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 英文標籤＋藍色中文；寬度不足時 [Wrap] 自動換行。
  Widget _buildBilingualLabel(String english, String chinese) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          english,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          chinese,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppConstants.signUpLinkBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildBilingualTitle() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        const Text(
          'Sign Up',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Text(
          '註冊',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppConstants.signUpLinkBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildBilingualSubtitle() {
    return Text(
      'Create your account to explore love.',
      style: TextStyle(
        fontSize: 15,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildLoginNameField() {
    return TextField(
      controller: _loginNameController,
      keyboardType: TextInputType.name,
      decoration: _inputDecoration(
        'Login name（登入名稱，至少 4 個字元）',
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: _inputDecoration('Email（電子郵件）'),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: _inputDecoration('Phone（電話）'),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _pwdController,
      obscureText: _obscurePwd,
      decoration: _inputDecoration('Password（密碼）').copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePwd ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
        ),
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextField(
      controller: _confirmPwdController,
      obscureText: _obscureConfirmPwd,
      decoration: _inputDecoration('Confirm Password（確認密碼）').copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPwd ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscureConfirmPwd = !_obscureConfirmPwd),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppConstants.loginButtonPurple, width: 1.5),
      ),
    );
  }
}
