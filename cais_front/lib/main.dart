import 'package:cais_front/app.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // 의존성 주입
  //Get.put(ApiService());
  //Get.put(AuthController());
  //Get.put(FeedController());

  runApp(const CAISApp());
}

