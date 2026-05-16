import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/app_controller.dart';
import 'home_tab.dart';
import 'search_tab.dart';
import 'wishlist_tab.dart';
import 'mypage_tab.dart';

const _kPrimary = Color(0xFF3B82F6);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _ctrl = Get.find<AppController>();
  Worker? _tabWorker;

  @override
  void initState() {
    super.initState();
    _tabWorker = ever(_ctrl.currentTab, (_) {
      if (mounted) setState(() {});
    });
    _ctrl.loadWishlist();
  }

  @override
  void dispose() {
    _tabWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          IndexedStack(
            index: _ctrl.currentTab.value,
            children: const [HomeTab(), SearchTab(), WishlistTab(), MypageTab()],
          ),
          // Toast overlay
          Obx(() => Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _ctrl.showingToast.value ? 1.0 : 0.0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171A3B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _ctrl.toastMessage.value,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
      bottomNavigationBar: Obx(() => BottomNavigationBar(
        currentIndex: _ctrl.currentTab.value,
        onTap: (i) => _ctrl.currentTab.value = i,
        selectedItemColor: _kPrimary,
        unselectedItemColor: const Color(0xFFC4C5CB),
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '검색'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), activeIcon: Icon(Icons.folder), label: '내 입찰'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'MY'),
        ],
      )),
    );
  }
}
