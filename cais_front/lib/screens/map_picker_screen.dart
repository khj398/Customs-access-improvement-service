import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/app_controller.dart';
import '../services/api_service.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kDanger = Color(0xFFB3261E);

/// 전체 화면 지도를 드래그해 위치를 고르고, 역지오코딩된 주소를 확인한 뒤
/// 저장하는 화면. 저장 성공 시 true를 반환하며 pop 된다.
class MapPickerScreen extends StatefulWidget {
  final LatLng initialCenter;
  const MapPickerScreen({super.key, required this.initialCenter});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapController = MapController();
  final _api = ApiService();

  late LatLng _center = widget.initialCenter;
  String? _roadAddress;
  String? _jibunAddress;
  bool _loadingAddress = true;
  bool _saving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchAddress();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchAddress() async {
    setState(() => _loadingAddress = true);
    final result = await _api.reverseGeocode(_center.latitude, _center.longitude);
    if (!mounted) return;
    setState(() {
      _roadAddress = result['roadAddress'];
      _jibunAddress = result['jibunAddress'];
      _loadingAddress = false;
    });
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _fetchAddress);
  }

  Future<void> _goToMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    } catch (_) {}
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await Get.find<AppController>().setLocationFromCoords(
      _center.latitude,
      _center.longitude,
      label: _roadAddress ?? _jibunAddress,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = _roadAddress != null || _jibunAddress != null;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: 16,
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.cais_front',
                ),
                RichAttributionWidget(
                  alignment: AttributionAlignment.bottomRight,
                  showFlutterMapAttribution: false,
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          ),

          // 화면 중앙에 고정된 핀 (지도가 움직여도 핀은 항상 중앙을 가리킴)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '바뀐 위치가 주소와 같은지 확인해주세요',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.location_on, color: _kPrimary, size: 44),
                  ],
                ),
              ),
            ),
          ),

          // 상단 바
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: const Text('지도에서 위치 확인',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),

          // 내 위치로 이동 버튼
          Positioned(
            right: 16,
            bottom: 220,
            child: _RoundIconButton(icon: Icons.gps_fixed, onTap: _goToMyLocation),
          ),

          // 하단 주소 확인/등록 패널
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingAddress)
                      const SizedBox(
                        height: 24,
                        child: Row(children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('주소 확인 중...', style: TextStyle(color: Color(0xFF8E919D), fontSize: 13)),
                        ]),
                      )
                    else ...[
                      Text(
                        _roadAddress ?? _jibunAddress ?? '주소를 찾을 수 없습니다',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      if (_roadAddress != null && _jibunAddress != null) ...[
                        const SizedBox(height: 4),
                        Text(_jibunAddress!, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 14)),
                      ],
                    ],
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '표시된 주소가 맞는지 확인해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _kDanger, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (hasAddress && !_saving) ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryDark,
                          disabledBackgroundColor: const Color(0xFFBFC2CC),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('이 위치로 주소 등록',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: const Color(0xFF1A1B33)),
        ),
      ),
    );
  }
}
