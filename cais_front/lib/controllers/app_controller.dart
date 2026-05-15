import 'package:get/get.dart';
import '../models/item.dart';
import '../data/items_data.dart';

class AppController extends GetxController {
  final wishlistIds = <int>[].obs;
  final activeCategory = '전체'.obs;
  final searchQuery = ''.obs;
  final currentTab = 0.obs;
  final newDropsMode = false.obs;

  final toastMessage = ''.obs;
  final showingToast = false.obs;

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
    final q = searchQuery.value.toLowerCase();
    if (q.isNotEmpty) {
      final terms = _expandSearch(q);
      list = list.where((i) {
        final target = '${i.name} ${i.cat} ${i.customs}'.toLowerCase();
        return terms.any((t) => target.contains(t));
      }).toList();
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

  List<String> _expandSearch(String query) {
    final dict = <String, List<String>>{
      '와인': ['wine'], '냉장고': ['refrigerator'], '제빙기': ['ice maker'],
      '바지': ['pants', 'shorts'], '신발': ['shoe', 'dress shoes', 'flat'],
      '조끼': ['vest'], '옷': ['pants', 'shorts', 'vest', 'woven'],
      '모니터': ['monitor', 'lcd'], '티비': ['tv'], '텔레비전': ['tv'],
      '램프': ['lamp'], '모기': ['mosquito'],
      '고추': ['red pepper', 'dried red pepper'],
      '초': ['candle'], '양초': ['candle'],
      '컵': ['cup', 'mug', 'glass', 'tumbler'], '머그': ['mug'],
      '접시': ['plate', 'bowl', 'tray'], '그릇': ['bowl', 'plate'],
      '면': ['cotton'], '원단': ['fabric', 'woven'],
      '팔찌': ['bracelet'], '런닝머신': ['treadmill'],
    };
    final terms = <String>[query];
    dict.forEach((ko, en) {
      if (query.contains(ko)) terms.addAll(en);
    });
    return terms;
  }
}
