import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../utils/format.dart';
import 'detail_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kDanger = Color(0xFFEF4444);

class WishlistTab extends StatelessWidget {
  const WishlistTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('찜한 상품',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1B33))),
            const SizedBox(height: 16),
            Expanded(
              child: Obx(() {
                ctrl.allItems.length; // wishedItems는 computed getter → 명시적 reactive 등록 필요
                ctrl.wishlistIds.length;
                final wished = ctrl.wishedItems;
                if (wished.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_border, size: 48, color: Color(0xFFB0B3BF)),
                        SizedBox(height: 12),
                        Text('찜한 상품이 없습니다', style: TextStyle(color: Color(0xFFB0B3BF), fontSize: 15)),
                        SizedBox(height: 4),
                        Text('관심있는 물품의 하트를 눌러 추가해보세요',
                            style: TextStyle(color: Color(0xFFB0B3BF), fontSize: 13)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: wished.length,
                  itemBuilder: (_, i) {
                    final item = wished[i];
                    return GestureDetector(
                      onTap: () => Get.to(() => DetailScreen(item: item)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEBEDF2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 90, height: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFE8E9EC), Color(0xFFDDE0E7)],
                                ),
                              ),
                              child: const Icon(Icons.inventory_2_outlined, size: 32, color: Color(0xFFA6ABB4)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.cat, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(item.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(formatPriceFull(item.price),
                                      style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => ctrl.toggleWish(item.id),
                              icon: const Icon(Icons.favorite, color: _kDanger, size: 24),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
