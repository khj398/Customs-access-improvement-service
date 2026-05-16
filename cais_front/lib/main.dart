import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'controllers/app_controller.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  Get.put(AppController());
  runApp(const CaisApp());
}

class CaisApp extends StatelessWidget {
  const CaisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '세관 경매 서비스',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      home: ApiService.isLoggedIn ? const MainScreen() : const LoginScreen(),
    );
  }
}
