import 'dart:async';
import 'package:get/get.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';

class AppController extends GetxController {
  final _api = ApiService();

  final allItems = <AuctionItem>[].obs;
  final searchResultItems = <AuctionItem>[].obs;
  final calendarItems = <AuctionItem>[].obs;
  final curatedItems = <AuctionItem>[].obs;
  // {cstmSgn, cstmName, itemCount} 목록 — 활성 물품 수 내림차순
  final nearbyCustoms = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;
  final currentPage = 1.obs;
  final hasMore = true.obs;

  final wishlistIds = <String>[].obs;

  // 카테고리 드릴다운 상태
  final l1Categories = <Map<String, dynamic>>[].obs;
  final l2Categories = <Map<String, dynamic>>[].obs;
  final l3Categories = <Map<String, dynamic>>[].obs;
  final activeL1 = Rxn<Map<String, dynamic>>();
  final activeL2 = Rxn<Map<String, dynamic>>();
  final activeL3 = Rxn<Map<String, dynamic>>();

  int? get activeCategoryId =>
      (activeL3.value?['categoryId'] ??
       activeL2.value?['categoryId'] ??
       activeL1.value?['categoryId']) as int?;

  final categoryStats = <int, int>{}.obs; // categoryId → 물품 건수
  final recentCategoryIds = <int>[];     // 검색탭 최근 선택 카테고리 (max 5)

  final searchQuery = ''.obs;
  final currentTab = 0.obs;
  final newDropsMode = false.obs;

  final toastMessage = ''.obs;
  final showingToast = false.obs;

  Timer? _searchDebounce;
  Timer? _autocompleteDebounce;
  int _autocompleteRequestId = 0;

  final suggestions = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadRootCategories();
    loadCategoryStats();
    _initData();
    loadWishlist();
  }

  Future<void> _initData() async {
    await loadItems();
    loadCuratedItems();
    loadNearbyCustoms();
  }

  Future<void> loadWishlist() async {
    try {
      final keys = await _api.fetchMyLikeKeys();
      wishlistIds.assignAll(keys);
    } catch (_) {}
  }

  Future<void> loadRootCategories() async {
    try {
      final cats = await _api.fetchCategories();
      l1Categories.assignAll(cats);
    } catch (_) {}
  }

  Future<void> loadCategoryStats() async {
    try {
      final stats = await _api.fetchCategoryStats();
      categoryStats.assignAll(stats);
    } catch (_) {}
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    _autocompleteDebounce?.cancel();
    super.onClose();
  }

  Future<void> loadItems() async {
    isLoading.value = true;
    hasError.value = false;
    try {
      final items = await _api.fetchItems(
        page: 1,
        limit: ApiConfig.defaultPageSize,
      );
      allItems.assignAll(items);
      searchResultItems.assignAll(items);
      currentPage.value = 1;
      hasMore.value = items.length >= ApiConfig.defaultPageSize;
    } on ApiException catch (e) {
      hasError.value = true;
      errorMessage.value = e.message;
    } catch (e) {
      hasError.value = true;
      errorMessage.value = '데이터를 불러올 수 없습니다.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadSearchItems() async {
    isLoading.value = true;
    hasError.value = false;
    try {
      final items = await _api.fetchItems(
        keyword: searchQuery.value.isEmpty ? null : searchQuery.value,
        categoryId: activeCategoryId,
        page: 1,
        limit: ApiConfig.defaultPageSize,
      );
      searchResultItems.assignAll(items);
      currentPage.value = 1;
      hasMore.value = items.length >= ApiConfig.defaultPageSize;
    } on ApiException catch (e) {
      hasError.value = true;
      errorMessage.value = e.message;
    } catch (e) {
      hasError.value = true;
      errorMessage.value = '데이터를 불러올 수 없습니다.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadNearbyCustoms() async {
    try {
      final list = await _api.fetchCustomsStats();
      nearbyCustoms.assignAll(list);
    } catch (_) {}
  }

  Future<void> loadCalendarItems(int year, int month) async {
    try {
      final items = await _api.fetchCalendarItems(year: year, month: month);
      calendarItems.assignAll(items);
    } catch (_) {}
  }

  Future<void> loadCuratedItems() async {
    // 찜한 상품의 cat 집합
    final wishedCats = allItems
        .where((i) => wishlistIds.contains(i.likeKey))
        .map((i) => i.cat)
        .toSet();

    // 최근 카테고리 ID로 추가 fetch
    final extra = <AuctionItem>[];
    if (recentCategoryIds.isNotEmpty) {
      try {
        final fetched = await _api.fetchItems(
          categoryId: recentCategoryIds.first,
          page: 1,
          limit: ApiConfig.defaultPageSize,
        );
        extra.addAll(fetched);
      } catch (_) {}
    }

    // 후보 풀: allItems + 추가 fetch (중복 제거)
    final seen = <String>{};
    final pool = <AuctionItem>[];
    for (final item in [...allItems, ...extra]) {
      if (seen.add(item.likeKey)) pool.add(item);
    }

    // 정렬: 찜 카테고리 매칭 > 최근 검색 카테고리 매칭 > 나머지
    pool.sort((a, b) {
      int scoreOf(AuctionItem i) {
        if (wishedCats.contains(i.cat)) return 0;
        if (recentCategoryIds.isNotEmpty) {
          // extra에 포함된 아이템은 최근 카테고리 기반
          if (extra.any((e) => e.likeKey == i.likeKey)) return 1;
        }
        return 2;
      }
      return scoreOf(a).compareTo(scoreOf(b));
    });

    // 찜 카테고리도 없고 최근 검색도 없으면 진행 중 전체 fallback
    if (wishedCats.isEmpty && recentCategoryIds.isEmpty) {
      curatedItems.assignAll(allItems.where((i) => i.status == '진행중').toList());
    } else {
      curatedItems.assignAll(pool);
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || !hasMore.value) return;
    isLoading.value = true;
    try {
      final nextPage = currentPage.value + 1;
      final items = await _api.fetchItems(
        keyword: searchQuery.value.isEmpty ? null : searchQuery.value,
        categoryId: activeCategoryId,
        page: nextPage,
        limit: ApiConfig.defaultPageSize,
      );
      searchResultItems.addAll(items);
      currentPage.value = nextPage;
      hasMore.value = items.length >= ApiConfig.defaultPageSize;
    } catch (_) {
      // 페이지네이션 실패는 조용히 무시
    } finally {
      isLoading.value = false;
    }
  }

  void searchItems(String query) {
    searchQuery.value = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      isLoading.value = true;
      hasError.value = false;
      try {
        final items = await _api.fetchItems(
          keyword: query.isEmpty ? null : query,
          categoryId: activeCategoryId,
          page: 1,
          limit: ApiConfig.defaultPageSize,
        );
        searchResultItems.assignAll(items);
        currentPage.value = 1;
        hasMore.value = items.length >= ApiConfig.defaultPageSize;
      } on ApiException catch (e) {
        hasError.value = true;
        errorMessage.value = e.message;
      } catch (_) {
        hasError.value = true;
        errorMessage.value = '검색 중 오류가 발생했습니다.';
      } finally {
        isLoading.value = false;
      }
    });
  }

  void fetchSuggestions(String q) {
    _autocompleteDebounce?.cancel();
    if (q.trim().isEmpty) {
      suggestions.clear();
      return;
    }
    // 요청 발사 전에 ID를 증가시켜 이전 응답을 무효화
    final requestId = ++_autocompleteRequestId;
    _autocompleteDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final results = await _api.fetchAutocomplete(q);
        // 응답이 돌아왔을 때 현재 ID와 다르면 더 최신 요청이 있으므로 버림
        if (requestId == _autocompleteRequestId) {
          suggestions.assignAll(results);
        }
      } catch (_) {
        if (requestId == _autocompleteRequestId) {
          suggestions.clear();
        }
      }
    });
  }

  void clearSuggestions() {
    _autocompleteDebounce?.cancel();
    _autocompleteRequestId++; // 진행 중인 요청 응답이 와도 무시하도록 무효화
    suggestions.clear();
  }

  void _recordCategoryId(int? id) {
    if (id == null) return;
    recentCategoryIds.remove(id);
    recentCategoryIds.insert(0, id);
    if (recentCategoryIds.length > 5) recentCategoryIds.removeLast();
  }

  Future<void> selectL1Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL1.value = cat;
    activeL2.value = null;
    activeL3.value = null;
    l2Categories.clear();
    l3Categories.clear();
    if (cat != null) {
      _recordCategoryId(cat['categoryId'] as int?);
      try {
        final children = await _api.fetchSubCategories(cat['categoryId'] as int);
        l2Categories.assignAll(children);
      } catch (_) {}
    }
    await loadSearchItems();
  }

  Future<void> selectL2Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL2.value = cat;
    activeL3.value = null;
    l3Categories.clear();
    if (cat != null) {
      _recordCategoryId(cat['categoryId'] as int?);
      try {
        final children = await _api.fetchSubCategories(cat['categoryId'] as int);
        l3Categories.assignAll(children);
      } catch (_) {}
    }
    await loadSearchItems();
  }

  Future<void> selectL3Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL3.value = cat;
    if (cat != null) _recordCategoryId(cat['categoryId'] as int?);
    await loadSearchItems();
  }

  Future<void> toggleWish(AuctionItem item) async {
    final key = item.likeKey;
    final wasWished = wishlistIds.contains(key);
    // 즉시 UI 반영 (낙관적 업데이트)
    if (wasWished) {
      wishlistIds.remove(key);
    } else {
      wishlistIds.add(key);
    }
    try {
      await _api.toggleLike(item.pbacNoStr, item.pbacSrno, item.cmdtLnNo);
      _toast(wasWished ? '찜 목록에서 제거되었습니다' : '찜 목록에 추가되었습니다 ♥');
      loadCuratedItems();
    } catch (e) {
      // 실패 시 롤백
      if (wasWished) {
        wishlistIds.add(key);
      } else {
        wishlistIds.remove(key);
      }
      _toast('찜 처리에 실패했습니다');
    }
  }

  bool isWished(String key) => wishlistIds.contains(key);

  void _toast(String msg) {
    toastMessage.value = msg;
    showingToast.value = true;
    Future.delayed(const Duration(milliseconds: 1800), () => showingToast.value = false);
  }

  List<AuctionItem> get filteredItems {
    if (newDropsMode.value) {
      return searchResultItems.where((i) => i.status == '진행중').toList();
    }
    return List<AuctionItem>.from(searchResultItems);
  }

  List<AuctionItem> get wishedItems =>
      allItems.where((i) => wishlistIds.contains(i.likeKey)).toList();

/// 같은 공매번호(pbacNo)에 속하는 다른 물품 목록 (번들 구매 필수 물품)
  List<AuctionItem> getBundledItems(AuctionItem target) {
    return allItems.where((i) =>
        i.pbacNoStr == target.pbacNoStr && i.cmdtLnNo != target.cmdtLnNo
    ).toList();
  }

  List<AuctionItem> getItemsForDay(DateTime day) {
    return calendarItems.where((i) {
      final d = i.endDay;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  void goToSearch({bool newDrops = false}) {
    newDropsMode.value = newDrops;
    if (!newDrops) {
      activeL1.value = null;
      activeL2.value = null;
      activeL3.value = null;
      l2Categories.clear();
      l3Categories.clear();
      searchQuery.value = '';
    }
    currentTab.value = 1;
  }
}
