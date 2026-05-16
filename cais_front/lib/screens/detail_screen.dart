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
                    // 번들 구매 필수 물품 섹션
                    Obx(() {
                      final bundled = ctrl.getBundledItems(item);
                      if (bundled.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E7),
                              border: Border.all(color: const Color(0xFFFFBD2E)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9500), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '이 공매는 ${bundled.length + 1}개 물품을 일괄 낙찰합니다.\n아래 물품도 반드시 함께 구매해야 합니다.',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...bundled.map((b) => _BundledCard(item: b)),
                        ],
                      );
                    }),
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

String _formatKst(String raw) {
  if (raw.isEmpty) return '-';
  try {
    final dt = DateTime.parse(raw.replaceAll(' ', 'T')).toUtc().add(const Duration(hours: 9));
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[dt.weekday - 1];
    final ampm = dt.hour < 12 ? '오전' : '오후';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 ($wd) $ampm $h:$m';
  } catch (_) {
    return raw;
  }
}

class _BundledCard extends StatelessWidget {
  final AuctionItem item;
  const _BundledCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => DetailScreen(item: item), preventDuplicates: false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FF),
          border: Border.all(color: const Color(0xFFE2E4EA)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAECF2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_outlined, size: 22, color: Color(0xFFA6ABB4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('수량: ${item.qty}  ·  중량: ${item.wght}',
                      style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0xFFC4C5CB), size: 20),
          ],
        ),
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
      ['공매번호', formatPbacNo(item.pbacNoStr)],
      ['세관명', item.customs],
      ['물품명', item.name],
      ['수량', item.qty],
      ['중량', item.wght],
      ['공매예정가격', formatPriceFull(item.price)],
      ['보세구역', item.warehouse],
      ['분류', item.cat],
      ['공매시작일시', _formatKst(item.startDate)],
      ['공매종료일시', _formatKst(item.endDate)],
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
