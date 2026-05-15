import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../widgets/item_card.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);

const _kCategories = ['전체', '산업·장비', '전자·전기', '가전', '생활·주방', '식품·음료', '의류·패션잡화', '기타'];

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _inputCtrl = TextEditingController();
  final _focus = FocusNode();
  late final AppController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.find<AppController>();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onInput(String val) {
    _ctrl.newDropsMode.value = false;
    _ctrl.searchItems(val);
  }

  void _clearSearch() {
    _inputCtrl.clear();
    _ctrl.newDropsMode.value = false;
    _ctrl.searchItems('');
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
      _ctrl.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DISCOVER',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1B33))),
                const SizedBox(height: 14),
                // Search bar
                Obx(() {
                  final hasText = _ctrl.searchQuery.value.isNotEmpty;
                  return Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAECF2),
                      border: Border.all(color: const Color(0xFFE2E4EA)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFFB0B3BF)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            focusNode: _focus,
                            onChanged: _onInput,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search for treasures...',
                              hintStyle: TextStyle(color: Color(0xFFB0B3BF), fontSize: 15),
                            ),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        if (hasText)
                          GestureDetector(
                            onTap: _clearSearch,
                            child: Container(
                              width: 24, height: 24,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC8CAD2)),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 14),

                // Category chips
                Obx(() => SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _kCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = _kCategories[i];
                      final active = _ctrl.activeCategory.value == cat;
                      return GestureDetector(
                        onTap: () {
                          _ctrl.activeCategory.value = cat;
                          _ctrl.newDropsMode.value = false;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: active ? _kPrimaryDark : const Color(0xFFE7E8EC),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                color: active ? Colors.white : const Color(0xFF7C7F8A),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              )),
                        ),
                      );
                    },
                  ),
                )),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Grid
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading.value && ctrl.allItems.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.hasError.value && ctrl.allItems.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Color(0xFFB0B3BF)),
                      const SizedBox(height: 10),
                      Text(ctrl.errorMessage.value,
                          style: const TextStyle(color: Color(0xFFB0B3BF))),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: ctrl.loadItems,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                );
              }
              final items = ctrl.filteredItems;
              if (items.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Color(0xFFB0B3BF)),
                      SizedBox(height: 10),
                      Text('검색 결과가 없습니다', style: TextStyle(color: Color(0xFFB0B3BF))),
                    ],
                  ),
                );
              }
              return NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: items.length + (ctrl.hasMore.value ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == items.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return ItemCard(item: items[i]);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  AppController get ctrl => _ctrl;
}
