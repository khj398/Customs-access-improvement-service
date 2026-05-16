import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../widgets/item_card.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kText = Color(0xFF1A1B33);

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return SafeArea(
      child: SingleChildScrollView(
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
                    onTap: () => ctrl.goToSearch(newDrops: true),
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
                  onTap: () => ctrl.goToSearch(),
                  child: const Text('SEE ALL', style: TextStyle(color: Color(0xFFB4B6BF), fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (ctrl.isLoading.value && ctrl.allItems.isEmpty) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (ctrl.hasError.value && ctrl.allItems.isEmpty) {
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
              final curated = ctrl.allItems.where((i) => i.status == '진행중').take(6).toList();
              return SizedBox(
                height: 240,
                child: curated.isEmpty
                    ? const Center(child: Text('진행 중인 공매가 없습니다', style: TextStyle(color: Color(0xFF9DA0AD))))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: curated.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => SizedBox(width: 160, child: ItemCard(item: curated[i], small: true)),
                      ),
              );
            }),
            const SizedBox(height: 20),

            // Live Auctions Nearby
            Row(
              children: const [
                Text('Live Auctions Nearby', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(width: 8),
                Icon(Icons.location_on, color: _kPrimary, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              ctrl.isLoading.value; // nearbyItems는 computed getter → 명시적 reactive 등록 필요
              final nearby = ctrl.nearbyItems;
              if (nearby.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('현재 진행 중인 인근 경매가 없습니다', style: TextStyle(color: Color(0xFF9DA0AD)))),
                );
              }
              return Column(
                children: nearby.entries.map((e) => _NearbyCard(loc: e.key, items: e.value)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _NearbyCard extends StatefulWidget {
  final String loc;
  final List items;
  const _NearbyCard({required this.loc, required this.items});

  @override
  State<_NearbyCard> createState() => _NearbyCardState();
}

class _NearbyCardState extends State<_NearbyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEBEDF2)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
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
                    Text('${widget.items.length} ITEMS ACTIVE',
                        style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                  ],
                ),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.chevron_right, color: const Color(0xFFC4C5CB)),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: widget.items.length > 4 ? 4 : widget.items.length,
              itemBuilder: (_, i) => ItemCard(item: widget.items[i]),
            ),
          ],
        ],
      ),
    );
  }
}
