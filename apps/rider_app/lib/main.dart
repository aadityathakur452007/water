import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/delivery/delivery_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.init();
  runApp(RiderApp(api: api));
}

class RiderApp extends StatefulWidget {
  const RiderApp({super.key, required this.api});

  final ApiClient api;

  @override
  State<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> {
  late bool _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = widget.api.isAuthenticated;
  }

  void _onLoginSuccess() {
    setState(() => _isAuthenticated = true);
  }

  void _onLogout() {
    setState(() => _isAuthenticated = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shodasha Rider',
      debugShowCheckedModeBanner: false,
      theme: ShodashaTheme.lightTheme,
      home: _isAuthenticated
          ? DeliveryScreen(
              api: widget.api,
              onLogout: _onLogout,
            )
          : LoginScreen(
              api: widget.api,
              onLoginSuccess: _onLoginSuccess,
            ),
    );
  }
}
