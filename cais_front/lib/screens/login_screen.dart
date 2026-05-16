import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _api = ApiService();

  // 로그인
  final _loginEmailCtrl    = TextEditingController();
  final _loginPwCtrl       = TextEditingController();
  // 회원가입
  final _regNameCtrl       = TextEditingController();
  final _regEmailCtrl      = TextEditingController();
  final _regPwCtrl         = TextEditingController();
  final _regPwConfirmCtrl  = TextEditingController();

  bool _loading = false;
  String? _error;

  static const _kPrimary     = Color(0xFF3B82F6);
  static const _kPrimaryDark = Color(0xFF171A3B);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tab.dispose();
    _loginEmailCtrl.dispose();
    _loginPwCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPwCtrl.dispose();
    _regPwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final pw    = _loginPwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해주세요');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _api.login(email, pw);
      _goMain();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '서버에 연결할 수 없습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final name  = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pw    = _regPwCtrl.text;
    final pw2   = _regPwConfirmCtrl.text;
    if (name.isEmpty || email.isEmpty || pw.isEmpty) {
      setState(() => _error = '모든 항목을 입력해주세요');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = '비밀번호가 일치하지 않습니다');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _api.register(email, pw, name);
      _goMain();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '서버에 연결할 수 없습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goMain() {
    Get.off(() => const MainScreen(), transition: Transition.fadeIn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('세관 경매',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _kPrimaryDark)),
                const SizedBox(height: 4),
                const Text('CUSTOMS AUCTION',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                        letterSpacing: 2)),
                const SizedBox(height: 36),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tab,
                        labelColor: _kPrimary,
                        unselectedLabelColor: const Color(0xFF9CA3AF),
                        indicatorColor: _kPrimary,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        tabs: const [Tab(text: '로그인'), Tab(text: '회원가입')],
                      ),
                      const Divider(height: 1),
                      SizedBox(
                        height: _tab.index == 0 ? 260 : 340,
                        child: TabBarView(
                          controller: _tab,
                          children: [_loginForm(), _registerForm()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _field('이메일', _loginEmailCtrl,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _field('비밀번호', _loginPwCtrl, obscure: true),
          const SizedBox(height: 20),
          _submitBtn('로그인', _login),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _field('이름', _regNameCtrl),
          const SizedBox(height: 10),
          _field('이메일', _regEmailCtrl,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field('비밀번호', _regPwCtrl, obscure: true),
          const SizedBox(height: 10),
          _field('비밀번호 확인', _regPwConfirmCtrl, obscure: true),
          const SizedBox(height: 18),
          _submitBtn('회원가입', _register),
        ],
      ),
    );
  }

  Widget _field(String hint, TextEditingController ctrl,
      {bool obscure = false, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      onSubmitted: (_) => _tab.index == 0 ? _login() : _register(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB0B3BF), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _submitBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: _loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimaryDark,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}
