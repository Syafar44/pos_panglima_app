import 'package:flutter/material.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Welcome Page")),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return LoginPage(title: "Login Page");
                },
              ),
            );
          },
          child: const Text("Login"),
        ),
      ),
    );
  }
}
