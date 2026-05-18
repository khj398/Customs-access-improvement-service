import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../widgets/item_card.dart';

class CuratedScreen extends StatelessWidget {
  const CuratedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('추천 물품',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1B33),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F5F8),
      body: Obx(() {
        final items = ctrl.curatedItems;

        if (ctrl.isLoading.value && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Color(0xFFD1D3DA)),
                SizedBox(height: 16),
                Text('추천 물품이 없습니다',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9DA0AD))),
                SizedBox(height: 8),
                Text('물품을 찜하거나 카테고리를 검색하면\n관련 물품을 추천해 드립니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFFB4B6BF))),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 320,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => ItemCard(item: items[i], imageHeight: 200),
        );
      }),
    );
  }
}
