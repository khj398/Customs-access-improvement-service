import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:table_calendar/table_calendar.dart';
import '../controllers/app_controller.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../utils/format.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kSuccess = Color(0xFF10B981);

class MypageTab extends StatefulWidget {
  const MypageTab({super.key});

  @override
  State<MypageTab> createState() => _MypageTabState();
}

class _MypageTabState extends State<MypageTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final _addressCtrl = TextEditingController();
  final _keywordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ctrl = Get.find<AppController>();
    ctrl.loadCalendarItems(_focusedDay.year, _focusedDay.month);
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MY PAGE',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1B33))),
            const SizedBox(height: 16),

            // Profile
            Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDBE7FF)),
                  child: const Icon(Icons.person, color: Color(0xFF3F7BE5), size: 30),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ApiService.userName.isNotEmpty ? ApiService.userName : '사용자',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(ApiService.userEmail,
                        style: const TextStyle(color: Color(0xFF8B8D95), fontSize: 14)),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Get.find<AppController>().wishlistIds.clear();
                    ApiService.logout();
                    Get.offAll(() => const LoginScreen(), transition: Transition.fadeIn);
                  },
                  icon: const Icon(Icons.logout, size: 16, color: Color(0xFF9CA3AF)),
                  label: const Text('로그아웃',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats
            Obx(() => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Row(
                children: [
                  _StatCell(value: '0', label: '입찰 참여', color: _kPrimary),
                  _StatCell(value: '0', label: '낙찰 성공', color: _kSuccess),
                  _StatCell(value: '${ctrl.wishlistIds.length}', label: '찜한 상품', color: _kPrimary),
                ],
              ),
            )),
            const SizedBox(height: 14),

            // 위치 설정
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.my_location, color: _kPrimary),
                      SizedBox(width: 8),
                      Text('내 위치 설정',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Obx(() {
                    final loc = ctrl.baseLocation.value;
                    final label = loc?['baseLocationLabel'] as String?;
                    final hasLoc = loc != null && loc['baseLatitude'] != null;
                    return Text(
                      hasLoc ? '현재 설정: ${label ?? '저장된 위치'}' : '설정된 위치가 없습니다',
                      style: const TextStyle(color: Color(0xFF8E919D), fontSize: 13),
                    );
                  }),
                  const SizedBox(height: 10),
                  Obx(() {
                    final loc = ctrl.baseLocation.value;
                    final lat = double.tryParse('${loc?['baseLatitude']}');
                    final lng = double.tryParse('${loc?['baseLongitude']}');
                    if (lat == null || lng == null) return const SizedBox.shrink();
                    final point = LatLng(lat, lng);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 160,
                        child: FlutterMap(
                          options: MapOptions(initialCenter: point, initialZoom: 15),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.cais_front',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: point,
                                width: 36,
                                height: 36,
                                child: const Icon(Icons.location_on, color: _kPrimary, size: 36),
                              ),
                            ]),
                            RichAttributionWidget(
                              alignment: AttributionAlignment.bottomRight,
                              showFlutterMapAttribution: false,
                              attributions: [
                                TextSourceAttribution('© OpenStreetMap contributors'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => ctrl.setLocationFromGps(),
                      icon: const Icon(Icons.gps_fixed, size: 18),
                      label: const Text('현재 위치로 설정'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addressCtrl,
                          decoration: InputDecoration(
                            hintText: '주소 직접 입력 (예: 인천 중구 서해대로 339)',
                            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B3BF)),
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final addr = _addressCtrl.text.trim();
                          if (addr.isEmpty) return;
                          ctrl.setLocationFromAddress(addr);
                          _addressCtrl.clear();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _kPrimaryDark),
                        child: const Text('저장'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 알림 on/off
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Obx(() => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: _kPrimary,
                title: const Text('푸시 알림 받기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: const Text('찜한 상품 경매 임박 · 관심 검색어 신규 물품 알림',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8E919D))),
                value: ctrl.notificationsEnabled.value,
                onChanged: ctrl.toggleNotifications,
              )),
            ),
            const SizedBox(height: 14),

            // 관심 검색어 관리
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: _kPrimary),
                      SizedBox(width: 8),
                      Text('관심 검색어',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keywordCtrl,
                          onSubmitted: (v) {
                            if (v.trim().isEmpty) return;
                            ctrl.subscribeToSearch(v.trim());
                            _keywordCtrl.clear();
                          },
                          decoration: InputDecoration(
                            hintText: '키워드 추가 (예: 와인)',
                            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B3BF)),
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final kw = _keywordCtrl.text.trim();
                          if (kw.isEmpty) return;
                          ctrl.subscribeToSearch(kw);
                          _keywordCtrl.clear();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _kPrimaryDark),
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Obx(() {
                    final subs = ctrl.searchSubscriptions;
                    if (subs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('구독 중인 검색어가 없습니다',
                            style: TextStyle(color: Color(0xFF9DA0AD), fontSize: 13)),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: subs.map((s) {
                        final id = s['subscriptionId'] as int;
                        final enabled = (s['notifyEnabled'] as num?)?.toInt() != 0;
                        return Chip(
                          label: Text(s['keyword'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: enabled ? const Color(0xFF1A1B33) : const Color(0xFFB0B3BF),
                              )),
                          backgroundColor: enabled ? const Color(0xFFEEF3FF) : const Color(0xFFF3F4F6),
                          onDeleted: () => ctrl.removeSearchSubscription(id),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          avatar: GestureDetector(
                            onTap: () => ctrl.toggleSearchSubscription(id, !enabled),
                            child: Icon(
                              enabled ? Icons.notifications_active : Icons.notifications_off,
                              size: 16,
                              color: enabled ? _kPrimary : const Color(0xFFB0B3BF),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Calendar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_month, color: _kPrimary),
                      SizedBox(width: 8),
                      Text('공매 일정 캘린더',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Obx(() {
                    final wishIds = ctrl.wishlistIds.toSet();
                    // calendarItems를 읽어서 Obx가 이 값의 변경도 추적하도록 함
                    // (그냥 eventLoader 안에서만 참조하면 GetX가 의존성을 감지 못해
                    //  비동기 로드가 끝나도 리빌드가 안 되고, 페이지 이동으로 강제
                    //  리빌드될 때만 최신 마커가 반영되는 문제가 있었음)
                    ctrl.calendarItems.length;
                    return TableCalendar<AuctionItem>(
                      firstDay: DateTime(2026, 1, 1),
                      lastDay: DateTime(2027, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                      eventLoader: ctrl.getItemsForDay,
                      onDaySelected: (selected, focused) {
                        setState(() {
                          _selectedDay = selected;
                          _focusedDay = focused;
                        });
                        final dayItems = ctrl.getItemsForDay(selected);
                        if (dayItems.isNotEmpty) _showDaySheet(context, selected, dayItems, wishIds);
                      },
                      onPageChanged: (focused) {
                        setState(() => _focusedDay = focused);
                        ctrl.loadCalendarItems(focused.year, focused.month);
                      },
                      calendarStyle: CalendarStyle(
                        todayDecoration: const BoxDecoration(color: _kPrimaryDark, shape: BoxShape.circle),
                        selectedDecoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: const BoxDecoration(color: Colors.transparent),
                        markersMaxCount: 2,
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return const SizedBox.shrink();
                          final hasWish = events.any((e) => wishIds.contains((e as AuctionItem).likeKey));
                          return Positioned(
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasWish) _dot(_kPrimary),
                                if (events.isNotEmpty) _dot(const Color(0xFFA78BFA)),
                              ],
                            ),
                          );
                        },
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Legend
                  Row(
                    children: [
                      _LegendDot(color: _kPrimary, label: '찜한 공매 마감일'),
                      const SizedBox(width: 16),
                      _LegendDot(color: const Color(0xFFA78BFA), label: '일반 공매 마감일'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 5, height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  void _showDaySheet(BuildContext context, DateTime day, List<AuctionItem> items, Set<String> wishIds) {
    final sorted = [...items]..sort((a, b) {
      final aW = wishIds.contains(a.likeKey) ? 0 : 1;
      final bW = wishIds.contains(b.likeKey) ? 0 : 1;
      return aW - bW;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD8D9DD), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1B33)),
                  children: [
                    TextSpan(text: '${day.month}월 ${day.day}일 마감 물품 '),
                    TextSpan(text: '${items.length}건', style: const TextStyle(color: _kPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: sorted.map((item) {
                    final isWished = wishIds.contains(item.likeKey);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => DetailScreen(item: item));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isWished ? const Color(0xFFEEF3FF) : const Color(0xFFF8F8FA),
                          borderRadius: BorderRadius.circular(12),
                          border: isWished ? Border.all(color: _kPrimary, width: 1.5) : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: isWished ? const Color(0xFFDBEAFE) : const Color(0xFFE8E9EC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isWished ? Icons.favorite : Icons.inventory_2_outlined,
                                color: isWished ? _kPrimary : const Color(0xFFA6ABB4),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                                          color: isWished ? _kPrimary : const Color(0xFF1A1B33))),
                                  Text(item.customs, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                                ],
                              ),
                            ),
                            Text(formatPrice(item.price),
                                style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
      ],
    );
  }
}
