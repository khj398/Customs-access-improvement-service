import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../widgets/item_card.dart';
import 'curated_screen.dart';
import 'customs_screen.dart';
import 'new_drops_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kText = Color(0xFF1A1B33);

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: ctrl.loadItems,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CUSTOMS AUCTION',
                style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text('디지털 세관',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, color: _kText)),
            const SizedBox(height: 14),

            // Search bar (tappable → search tab)
            GestureDetector(
              onTap: () => ctrl.goToSearch(),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAECF2),
                  border: Border.all(color: const Color(0xFFE2E4EA)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: Color(0xFFB0B3BF)),
                    SizedBox(width: 10),
                    Text('가장 가치있는 물품을 찾아보세요',
                        style: TextStyle(color: Color(0xFFB0B3BF), fontSize: 15)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Hero banner
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F345F), Color(0xFF2A4A8A)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF60A5FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('NEW DROP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  const Text('이번 주 새로 등록된 공매',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Get.to(() => const NewDropsScreen()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('자세히 보기',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Curated For You
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Curated For You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                GestureDetector(
                  onTap: () => Get.to(() => const CuratedScreen()),
                  child: const Text('SEE ALL', style: TextStyle(color: Color(0xFFB4B6BF), fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (ctrl.isLoading.value && ctrl.curatedItems.isEmpty) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (ctrl.hasError.value && ctrl.curatedItems.isEmpty) {
                return SizedBox(
                  height: 240,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(ctrl.errorMessage.value,
                            style: const TextStyle(color: Color(0xFF9DA0AD))),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: ctrl.loadItems,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final curated = ctrl.curatedItems.take(6).toList();
              if (curated.isEmpty) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: Text('진행 중인 공매가 없습니다', style: TextStyle(color: Color(0xFF9DA0AD)))),
                );
              }
              return SizedBox(
                height: 240,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  }),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: curated.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(width: 160, child: ItemCard(item: curated[i], small: true)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),

            // Customs Overview
            Row(
              children: const [
                Text('전국 세관 현황', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(width: 8),
                Icon(Icons.account_balance, color: _kPrimary, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              final customs = ctrl.nearbyCustoms;
              if (customs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('세관 정보를 불러오는 중입니다', style: TextStyle(color: Color(0xFF9DA0AD)))),
                );
              }
              return Column(
                children: customs.map((c) => _NearbyCard(
                  loc: (c['cstmName'] as String?) ?? '',
                  itemCount: (c['itemCount'] as num?)?.toInt() ?? 0,
                  cstmSgn: (c['cstmSgn'] as String?) ?? '',
                )).toList(),
              );
            }),
          ],
        ),
      ),
      ),
    );
  }
}

class _NearbyCard extends StatefulWidget {
  final String loc;
  final int itemCount;
  final String cstmSgn;
  const _NearbyCard({required this.loc, required this.itemCount, required this.cstmSgn});

  @override
  State<_NearbyCard> createState() => _NearbyCardState();
}

class _NearbyCardState extends State<_NearbyCard> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => CustomsScreen(
            customs: widget.loc,
            cstmSgn: widget.cstmSgn,
          )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEBEDF2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDBEAFE)),
              child: const Icon(Icons.location_on, color: _kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.loc, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${widget.itemCount} ITEMS ACTIVE',
                    style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFFC4C5CB)),
          ],
        ),
      ),
    );
  }
}
