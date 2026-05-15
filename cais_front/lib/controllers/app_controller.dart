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

  final wishlistIds = <int>[].obs;
  final activeCategory = '전체'.obs;
  final searchQuery = ''.obs;
  final currentTab = 0.obs;
  final newDropsMode = false.obs;

  final toastMessage = ''.obs;
  final showingToast = false.obs;

  Timer? _searchDebounce;

  @override
  void onInit() {
    super.onInit();
    loadItems();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    super.onClose();
  }

  Future<void> loadItems() async {
    isLoading.value = true;
    hasError.value = false;
    try {
      final items = await _api.fetchItems(page: 1, limit: ApiConfig.defaultPageSize);
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

  void toggleWish(int id) {
    if (wishlistIds.contains(id)) {
      wishlistIds.remove(id);
      _toast('찜 목록에서 제거되었습니다');
    } else {
      wishlistIds.add(id);
      _toast('찜 목록에 추가되었습니다 ♥');
    }
  }

  bool isWished(int id) => wishlistIds.contains(id);

  void _toast(String msg) {
    toastMessage.value = msg;
    showingToast.value = true;
    Future.delayed(const Duration(milliseconds: 1800), () => showingToast.value = false);
  }

  List<AuctionItem> get filteredItems {
    var list = List<AuctionItem>.from(allItems);
    if (newDropsMode.value) {
      return list.where((i) => i.status == '진행중').toList();
    }
    if (activeCategory.value != '전체') {
      list = list.where((i) => i.cat == activeCategory.value).toList();
    }
    return list;
  }

  List<AuctionItem> get wishedItems =>
      allItems.where((i) => wishlistIds.contains(i.id)).toList();

  Map<String, List<AuctionItem>> get nearbyItems {
    final result = <String, List<AuctionItem>>{};
    for (final loc in ['인천세관', '부산세관', '서울세관', '광양세관']) {
      final items = allItems.where((i) => i.customs == loc && i.status == '진행중').toList();
      if (items.isNotEmpty) result[loc] = items;
    }
    return result;
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
      activeCategory.value = '전체';
      searchQuery.value = '';
    }
    currentTab.value = 1;
  }
}
