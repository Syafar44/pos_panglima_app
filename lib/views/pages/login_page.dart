import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/views/widgets/startsift_modal.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});

  final String title;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController controllerEmail = TextEditingController();
  TextEditingController controllerPw = TextEditingController();
  final apiClient = ApiClient();
  late final AuthService authService;

  bool loading = false;
  bool _isObscure = true;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
  }

  // Future<void> login() async {
  //   setState(() => loading = true);

  //   try {
  //     final response = await authService.login({
  //       "email": controllerEmail.text,
  //       "password": controllerPw.text,
  //     });

  //     print(response.data['data']['token']);

  //     final token = response.data['data']['token'];
  //     await apiClient.saveToken(token);

  //     if (!mounted) return;
  //     showDialog(
  //       context: context,
  //       barrierDismissible: true,
  //       builder: (BuildContext context) {
  //         return const StartsiftModal();
  //       },
  //     );
  //   } catch (e) {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(const SnackBar(content: Text("Login gagal")));
  //   }

  //   setState(() => loading = false);
  // }

  Future<void> login() async {
    if (!mounted) return;

    setState(() => loading = true);

    try {
      final response = await authService.login({
        "email": controllerEmail.text,
        "password": controllerPw.text,
      });

      final roles = response.data['data']['roles'];

      if (!roles.toLowerCase().contains('kasir')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Bukan Akun KASIR")));
        return;
      }

      final token = response.data['data']['token'];
      await apiClient.saveToken(token);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
        builder: (_) => const StartsiftModal(),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Login gagal")));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/background.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Center(
              child: Container(
                width: 600.0,
                height: 450.0,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(),
                      spreadRadius: 5,
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 150.0,
                        ),
                      ),
                      SizedBox(height: 20.0),
                      Text(
                        'Masuk Sekarang',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20.0,
                        ),
                      ),
                      SizedBox(height: 20.0),
                      TextField(
                        controller: controllerEmail,
                        decoration: InputDecoration(
                          hintText: 'Email',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                        ),
                        onEditingComplete: () => setState(() {}),
                      ),
                      SizedBox(height: 10.0),
                      TextField(
                        controller: controllerPw,
                        obscureText: _isObscure,
                        decoration: InputDecoration(
                          hintText: 'Kata Sandi',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isObscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _isObscure = !_isObscure;
                              });
                            },
                          ),
                        ),
                        onEditingComplete: () => setState(() {}),
                      ),
                      SizedBox(height: 20.0),
                      ElevatedButton(
                        onPressed: () {
                          loading ? null : login();
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 40.0),
                          backgroundColor: Colors.amber,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.0),
                          ),
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Masuk",
                                style: TextStyle(color: Colors.black),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
