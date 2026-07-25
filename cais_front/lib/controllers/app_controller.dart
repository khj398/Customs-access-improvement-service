import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';
import '../services/local_notification_service.dart';

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
  final wishlistItems = <AuctionItem>[].obs;

  // 위치 기반 세관 추천
  final baseLocation = Rxn<Map<String, dynamic>>();

  // 알림 on/off (기기 토큰 등록 여부로 반영)
  static const _kNotifyPref = 'notify_enabled';
  final notificationsEnabled = true.obs;

  // 관심 검색어 구독
  final searchSubscriptions = <Map<String, dynamic>>[].obs;

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
    FirebaseMessaging.onMessage.listen((msg) {
      final title = msg.notification?.title ?? '알림';
      final body = msg.notification?.body ?? '';
      // foreground에서는 FCM이 시스템 알림을 자동으로 안 띄우므로 직접 띄워서
      // 알림창에 남도록 함 (background/killed 상태와 동일한 사용자 경험)
      LocalNotificationService.show(title, body);
    });
  }

  Future<void> _initData() async {
    await loadItems();
    await loadWishlist();
    loadCuratedItems();
    loadNearbyCustoms();

    notificationsEnabled.value = GetStorage().read<bool>(_kNotifyPref) ?? true;
    if (ApiService.isLoggedIn) {
      loadBaseLocation();
      loadSearchSubscriptions();
      registerPushToken();
    }
  }

  Future<void> loadBaseLocation() async {
    baseLocation.value = await _api.fetchBaseLocation();
  }

  Future<void> setLocationFromGps({String? label}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _toast('위치 권한이 필요합니다');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('기기의 위치 서비스를 켜주세요');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final loc = await _api.updateBaseLocationGps(pos.latitude, pos.longitude, label: label);
      baseLocation.value = loc;
      _toast('현재 위치로 설정되었습니다');
      loadNearbyCustoms();
    } catch (_) {
      _toast('위치를 가져오지 못했습니다');
    }
  }

  Future<void> setLocationFromAddress(String address, {String? label}) async {
    try {
      final loc = await _api.updateBaseLocationAddress(address, label: label ?? address);
      baseLocation.value = loc;
      _toast('위치가 저장되었습니다');
      loadNearbyCustoms();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('위치 저장에 실패했습니다');
    }
  }

  Future<void> registerPushToken() async {
    if (!ApiService.isLoggedIn || !notificationsEnabled.value) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _api.registerDeviceToken(token);
    } catch (_) {}
  }

  Future<void> toggleNotifications(bool value) async {
    notificationsEnabled.value = value;
    GetStorage().write(_kNotifyPref, value);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      if (value) {
        await _api.registerDeviceToken(token);
        _toast('알림이 켜졌습니다');
      } else {
        await _api.removeDeviceToken(token);
        _toast('알림이 꺼졌습니다');
      }
    } catch (_) {}
  }

  Future<void> loadSearchSubscriptions() async {
    final list = await _api.fetchSearchSubscriptions();
    searchSubscriptions.assignAll(list);
    loadCuratedItems();
  }

  bool isSubscribedKeyword(String keyword) => subscriptionFor(keyword) != null;

  Map<String, dynamic>? subscriptionFor(String keyword) {
    final k = keyword.trim().toLowerCase();
    for (final s in searchSubscriptions) {
      if ((s['keyword'] as String).trim().toLowerCase() == k) return s;
    }
    return null;
  }

  Future<void> subscribeToSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    try {
      await _api.addSearchSubscription(keyword.trim());
      _toast('"$keyword" 신규 물품 알림을 구독했습니다');
      await loadSearchSubscriptions();
    } catch (_) {
      _toast('구독에 실패했습니다');
    }
  }

  Future<void> removeSearchSubscription(int subscriptionId) async {
    try {
      await _api.removeSearchSubscription(subscriptionId);
      searchSubscriptions.removeWhere((s) => s['subscriptionId'] == subscriptionId);
      _toast('구독을 삭제했습니다');
      loadCuratedItems();
    } catch (_) {
      _toast('삭제에 실패했습니다');
    }
  }

  Future<void> toggleSearchSubscription(int subscriptionId, bool enabled) async {
    try {
      await _api.toggleSearchSubscription(subscriptionId, enabled);
      final idx = searchSubscriptions.indexWhere((s) => s['subscriptionId'] == subscriptionId);
      if (idx != -1) {
        searchSubscriptions[idx] = {...searchSubscriptions[idx], 'notifyEnabled': enabled ? 1 : 0};
        searchSubscriptions.refresh();
        loadCuratedItems();
      }
    } catch (_) {}
  }

  Future<void> loadWishlist() async {
    try {
      final keys = await _api.fetchMyLikeKeys();
      wishlistIds.assignAll(keys);
      final items = await _api.fetchMyLikeItems();
      wishlistItems.assignAll(items);
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

  // 관심 검색어(구독 키워드) 기반 추천 — 키워드가 없으면 진행 중 전체로 fallback
  Future<void> loadCuratedItems() async {
    final keywords = searchSubscriptions
        .where((s) => (s['notifyEnabled'] as num?)?.toInt() != 0)
        .map((s) => (s['keyword'] as String).trim())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList();

    if (keywords.isEmpty) {
      curatedItems.assignAll(allItems.where((i) => i.status == '진행중').toList());
      return;
    }

    // 키워드별로 매칭 물품 fetch
    final extra = <AuctionItem>[];
    for (final kw in keywords) {
      try {
        final fetched = await _api.fetchItems(keyword: kw, page: 1, limit: ApiConfig.defaultPageSize);
        extra.addAll(fetched);
      } catch (_) {}
    }

    // 후보 풀: 키워드 매칭 결과 + allItems (중복 제거)
    final seen = <String>{};
    final pool = <AuctionItem>[];
    for (final item in [...extra, ...allItems]) {
      if (seen.add(item.likeKey)) pool.add(item);
    }

    int matchCount(AuctionItem i) {
      final name = i.name.toLowerCase();
      return keywords.where((k) => name.contains(k.toLowerCase())).length;
    }

    // 매칭 키워드 많은 순으로 정렬, 매칭된 것만 채택
    pool.sort((a, b) => matchCount(b).compareTo(matchCount(a)));
    final matched = pool.where((i) => matchCount(i) > 0).toList();

    // 매칭 결과가 너무 적으면 진행 중 물품으로 채워서 빈 화면 방지
    if (matched.length < 4) {
      final filler = pool.where((i) => matchCount(i) == 0 && i.status == '진행중');
      matched.addAll(filler);
    }
    curatedItems.assignAll(matched);
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
      wishlistItems.removeWhere((i) => i.likeKey == key);
    } else {
      wishlistIds.add(key);
      wishlistItems.add(item);
    }
    try {
      await _api.toggleLike(item.pbacNoStr, item.pbacSrno, item.cmdtLnNo);
      _toast(wasWished ? '찜 목록에서 제거되었습니다' : '찜 목록에 추가되었습니다 ♥');
    } catch (e) {
      // 실패 시 롤백
      if (wasWished) {
        wishlistIds.add(key);
        wishlistItems.add(item);
      } else {
        wishlistIds.remove(key);
        wishlistItems.removeWhere((i) => i.likeKey == key);
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
