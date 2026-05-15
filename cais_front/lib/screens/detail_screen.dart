import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/item.dart';
import '../controllers/app_controller.dart';
import '../utils/format.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kSuccess = Color(0xFF10B981);
const _kDanger = Color(0xFFEF4444);

class DetailScreen extends StatelessWidget {
  final AuctionItem item;
  const DetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero image
            SizedBox(
              height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE0E1E5), Color(0xFFD0D2D8)],
                      ),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, size: 80, color: Color(0xFFA6ABB4)),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CircleBtn(
                            icon: Icons.arrow_back,
                            onTap: () => Get.back(),
                          ),
                          Obx(() {
                            final liked = ctrl.isWished(item.id);
                            return _CircleBtn(
                              icon: liked ? Icons.favorite : Icons.favorite_border,
                              iconColor: liked ? _kDanger : Colors.black87,
                              onTap: () => ctrl.toggleWish(item.id),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Panel
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.cat, style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(item.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CURRENT PRICE', style: TextStyle(color: Color(0xFFA6A8B1), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(formatPriceFull(item.price), style: const TextStyle(color: _kPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('STATUS', style: TextStyle(color: Color(0xFFA6A8B1), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  item.status == '진행중' ? Icons.access_time : Icons.circle,
                                  size: 14,
                                  color: item.status == '진행중' ? _kSuccess : const Color(0xFF8E919D),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.status,
                                  style: TextStyle(
                                    color: item.status == '진행중' ? _kSuccess : const Color(0xFF8E919D),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Lot info title
                    Container(
                      padding: const EdgeInsets.only(left: 10),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: _kPrimary, width: 3)),
                      ),
                      child: const Text('Lot Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 12),
                    _LotTable(item: item),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Get.snackbar('준비 중', '입찰 기능은 준비 중입니다.',
                            backgroundColor: _kPrimaryDark, colorText: Colors.white,
                            snackPosition: SnackPosition.BOTTOM),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Place Your Bid', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
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

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: iconColor ?? Colors.black87),
      ),
    );
  }
}

class _LotTable extends StatelessWidget {
  final AuctionItem item;
  const _LotTable({required this.item});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['세관명', item.customs],
      ['물품명', item.name],
      ['수량', item.qty],
      ['중량', item.wght],
      ['공매예정가격', formatPriceFull(item.price)],
      ['보세구역', item.warehouse],
      ['분류', item.cat],
      ['공매시작일시', item.startDate],
      ['공매종료일시', item.endDate],
    ];

    return Column(
      children: rows.map((r) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5)))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(r[0], style: const TextStyle(color: Color(0xFF8E919D), fontSize: 14)),
            const SizedBox(width: 16),
            Flexible(
              child: Text(r[1], textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
