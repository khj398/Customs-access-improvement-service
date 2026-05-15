import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../data/items_data.dart';
import '../widgets/item_card.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);

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
    _ctrl.searchQuery.value = val;
    _ctrl.newDropsMode.value = false;
  }

  void _clearSearch() {
    _inputCtrl.clear();
    _ctrl.searchQuery.value = '';
    _ctrl.newDropsMode.value = false;
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
                    itemCount: kCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = kCategories[i];
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
              final items = _ctrl.filteredItems;
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
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => ItemCard(item: items[i]),
              );
            }),
          ),
        ],
      ),
    );
  }
}
