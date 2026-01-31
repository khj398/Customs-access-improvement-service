# CAIS Frontend (cais_front) 🚢

**설명**

CAIS( Customs Access Improvement Service )의 Flutter 기반 모바일/웹 프론트엔드 애플리케이션입니다. 이 프로젝트는 사용자 인증, 위치 기반 서비스, 검색/등록, 좋아요(찜) 기능 등 주요 화면과 서비스를 포함합니다.

---

## 주요 기능 ✅

- 사용자 로그인/회원가입
- 메인 홈, 검색, 상세, 등록, 마이페이지 등 화면
- 위치 기반 검색 및 마이페이지 위치 관리
- 아이템 찜(좋아요) 기능

---

## 기술 스택 🔧

- Flutter (Dart)
- Android / iOS / web / desktop 빌드 지원
- 주요 라이브러리: (프로젝트 내 pubspec.yaml 참조)

---

## 빠른 시작 ✨

1. 의존성 설치

```bash
flutter pub get
```

2. 개발용 실행(디바이스 선택)

```bash
flutter run -d <device-id>
# 예: flutter run -d emulator-5554
```

3. 빌드 (릴리스)

- Android

```bash
flutter build apk --release
```

- iOS

```bash
flutter build ios --release
```

- Web

```bash
flutter build web
```

---

## 프로젝트 구조 📁

- `lib/` : 앱 소스 코드
  - `screens/` : 화면 위젯들
  - `widgets/` : 재사용 위젯
  - `controllers/`, `services/`, `models/`

---

## 설정 및 환경 🔒

- Android의 경우 `local.properties`에 Android SDK 경로 등이 있어야 합니다.
- 백엔드 API URL 등 민감정보는 환경변수 또는 별도 설정 파일로 관리하세요.

---

## 테스트 및 디버깅 🧪

- 디버깅: `flutter run --debug`

© 프로젝트: Customs-access-improvement-service

