import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/item.dart';
import '../controllers/app_controller.dart';
import '../utils/format.dart';
import '../screens/detail_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kDanger = Color(0xFFEF4444);

class ItemCard extends StatelessWidget {
  final AuctionItem item;
  final bool small;

  const ItemCard({super.key, required this.item, this.small = false});

  Widget _buildPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8E9EC), Color(0xFFDDE0E7)],
          ),
        ),
        child: const Icon(Icons.inventory_2_outlined, size: 40, color: Color(0xFFA6ABB4)),
      );

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();
    final thumbH = small ? 120.0 : 148.0;

    return GestureDetector(
      onTap: () => Get.to(() => DetailScreen(item: item)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEBEDF2)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: thumbH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.images.isNotEmpty
                      ? Image.network(
                          item.images.first,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                  Positioned(
                    top: 8, right: 8,
                    child: Obx(() {
                      final liked = ctrl.isWished(item.likeKey);
                      return GestureDetector(
                        onTap: () => ctrl.toggleWish(item),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(liked ? 0.95 : 0.85),
                          ),
                          child: Icon(
                            liked ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: liked ? _kDanger : const Color(0xFF9DA0AD),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.cat,
                            style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800, height: 1.3),
                        ),
                      ],
                    ),
                    Text(
                      formatPriceFull(item.price),
                      style: const TextStyle(
                          color: _kPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
