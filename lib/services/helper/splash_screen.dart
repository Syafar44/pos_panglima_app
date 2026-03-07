import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiClient apiClient = ApiClient();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkLogin();
    });
  }

  Future<void> checkLogin() async {
    await Future.delayed(const Duration(seconds: 1));

    final token = await apiClient.getToken();

    if (!mounted) return;

    if (token != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage(title: 'Login Page')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
