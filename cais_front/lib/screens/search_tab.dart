import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import '../widgets/item_card.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  };
}

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
    ever(_ctrl.searchQuery, (String q) {
      if (_inputCtrl.text != q) _inputCtrl.text = q;
    });
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
    _ctrl.fetchSuggestions(val);
  }

  void _clearSearch() {
    _inputCtrl.clear();
    _ctrl.newDropsMode.value = false;
    _ctrl.searchItems('');
    _ctrl.clearSuggestions();
  }

  void _onSuggestionTap(String suggestion) {
    _inputCtrl.text = suggestion;
    _inputCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    _ctrl.searchItems(suggestion);
    _ctrl.clearSuggestions();
    _focus.unfocus();
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
                const SizedBox(height: 6),

                // 자동완성 제안 목록
                Obx(() {
                  final sugs = _ctrl.suggestions.toList();
                  if (sugs.isEmpty) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E4EA)),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: sugs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final s = entry.value;
                        return InkWell(
                          onTap: () => _onSuggestionTap(s),
                          borderRadius: BorderRadius.vertical(
                            top: i == 0 ? const Radius.circular(16) : Radius.zero,
                            bottom: i == sugs.length - 1
                                ? const Radius.circular(16)
                                : Radius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.search,
                                    size: 16, color: Color(0xFFB0B3BF)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1A1B33),
                                    ),
                                  ),
                                ),
                                const Icon(Icons.north_west,
                                    size: 14, color: Color(0xFFB0B3BF)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }),

                // Category drilldown chips (대분류 → 중분류 → 소분류)
                Obx(() {
                  final sugsVisible = _ctrl.suggestions.isNotEmpty;
                  final l1 = _ctrl.l1Categories.toList();
                  final l2 = _ctrl.l2Categories.toList();
                  final l3 = _ctrl.l3Categories.toList();
                  final activeL1Id = _ctrl.activeL1.value?['categoryId'] as int?;
                  final activeL2Id = _ctrl.activeL2.value?['categoryId'] as int?;
                  final activeL3Id = _ctrl.activeL3.value?['categoryId'] as int?;

                  final stats = Map<int, int>.from(_ctrl.categoryStats);

                  if (l1.isEmpty || sugsVisible) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _chipRow(l1, activeL1Id, 42, 14,
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          (cat) => _ctrl.selectL1Category(cat), stats: stats),
                      if (l2.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _chipRow(l2, activeL2Id, 36, 12,
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            (cat) => _ctrl.selectL2Category(cat), stats: stats),
                      ],
                      if (l3.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _chipRow(l3, activeL3Id, 32, 11,
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            (cat) => _ctrl.selectL3Category(cat), stats: stats),
                      ],
                    ],
                  );
                }),
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
              return RefreshIndicator(
                onRefresh: ctrl.loadItems,
                child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    // 화면 폭에 따라 열 수 결정
                    final cols = w < 520 ? 2 : w < 900 ? 3 : 4;
                    // 카드 고정 높이: 이미지 148 + 텍스트 영역 82 = 230px
                    const cardH = 230.0;
                    final hPad = 18.0 * 2;
                    final gap = 12.0 * (cols - 1);
                    final cardW = (w - hPad - gap) / cols;
                    final ratio = cardW / cardH;
                    return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: ratio,
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
                );
                  },
                ),
              ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _chipRow(
    List<Map<String, dynamic>> cats,
    int? activeId,
    double height,
    double fontSize,
    EdgeInsets padding,
    void Function(Map<String, dynamic>?) onSelect, {
    Map<int, int> stats = const {},
  }) {
    return SizedBox(
      height: height,
      child: ScrollConfiguration(
        behavior: _MouseDragScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cats.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == 0) {
              return _chip('전체', activeId == null, padding, fontSize, () => onSelect(null));
            }
            final cat = cats[i - 1];
            final catId = cat['categoryId'] as int?;
            final count = catId != null ? (stats[catId] ?? 0) : 0;
            final isActive = activeId == catId;
            return _chip(cat['nameKo'] as String, isActive, padding, fontSize,
                () => onSelect(cat), count: count);
          },
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, EdgeInsets padding, double fontSize,
      VoidCallback onTap, {int count = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: active ? _kPrimaryDark : const Color(0xFFE7E8EC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF7C7F8A),
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                )),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count',
                  style: TextStyle(
                    color: active ? Colors.white.withOpacity(0.75) : const Color(0xFFADB0BA),
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize - 1,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  AppController get ctrl => _ctrl;
}
