import 'dart:async';
import 'package:get/get.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';

class AppController extends GetxController {
  final _api = ApiService();

  final allItems = <AuctionItem>[].obs;
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
    loadItems();
    loadWishlist();
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
        categoryId: activeCategoryId,
        page: 1,
        limit: ApiConfig.defaultPageSize,
      );
      allItems.assignAll(items);
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
      allItems.addAll(items);
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
        allItems.assignAll(items);
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

  Future<void> selectL1Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL1.value = cat;
    activeL2.value = null;
    activeL3.value = null;
    l2Categories.clear();
    l3Categories.clear();
    if (cat != null) {
      try {
        final children = await _api.fetchSubCategories(cat['categoryId'] as int);
        l2Categories.assignAll(children);
      } catch (_) {}
    }
    await loadItems();
  }

  Future<void> selectL2Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL2.value = cat;
    activeL3.value = null;
    l3Categories.clear();
    if (cat != null) {
      try {
        final children = await _api.fetchSubCategories(cat['categoryId'] as int);
        l3Categories.assignAll(children);
      } catch (_) {}
    }
    await loadItems();
  }

  Future<void> selectL3Category(Map<String, dynamic>? cat) async {
    newDropsMode.value = false;
    activeL3.value = cat;
    await loadItems();
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
      return allItems.where((i) => i.status == '진행중').toList();
    }
    return List<AuctionItem>.from(allItems);
  }

  List<AuctionItem> get wishedItems =>
      allItems.where((i) => wishlistIds.contains(i.likeKey)).toList();

  Map<String, List<AuctionItem>> get nearbyItems {
    final result = <String, List<AuctionItem>>{};
    for (final loc in ['인천세관', '부산세관', '서울세관', '광양세관']) {
      final items = allItems.where((i) => i.customs == loc && i.status == '진행중').toList();
      if (items.isNotEmpty) result[loc] = items;
    }
    return result;
  }

  /// 같은 공매번호(pbacNo)에 속하는 다른 물품 목록 (번들 구매 필수 물품)
  List<AuctionItem> getBundledItems(AuctionItem target) {
    return allItems.where((i) =>
        i.pbacNoStr == target.pbacNoStr && i.cmdtLnNo != target.cmdtLnNo
    ).toList();
  }

  List<AuctionItem> getItemsForDay(DateTime day) {
    return allItems.where((i) {
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
