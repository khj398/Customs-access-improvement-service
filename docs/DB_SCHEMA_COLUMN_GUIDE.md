# DB 스키마 컬럼 설명서

이 문서는 현재 프로젝트의 DB 스키마 컬럼 의미를 빠르게 이해하기 위한 가이드입니다.

- 기준 파일: `db/schema_create.sql`
- 보완 논의: `docs/DB_REDESIGN_DISCUSSION.md`

---

## 1) 공매 코어(`auction_core` 성격) - 기존/핵심 테이블

### 1-1. `customs_office` (세관 마스터)
| 컬럼 | 설명 |
|---|---|
| `cstm_sgn` | 세관부호(PK) |
| `cstm_name` | 세관명 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 1-2. `bonded_warehouse` (보세창고 마스터)
| 컬럼 | 설명 |
|---|---|
| `snar_sgn` | 창고부호(PK) |
| `snar_name` | 창고명 |
| `cstm_sgn` | 관할 세관부호(FK, nullable) |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 1-3. `cargo_type` (화물유형 마스터)
| 컬럼 | 설명 |
|---|---|
| `cargo_tpcd` | 화물유형코드(PK) |
| `cargo_name` | 화물유형명 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 1-4. `unit_code` (단위코드 마스터)
| 컬럼 | 설명 |
|---|---|
| `unit_cd` | 단위코드(PK) |
| `unit_name` | 단위명 |
| `unit_kind` | 단위 종류(QTY/WEIGHT/OTHER) |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 1-5. `auction` (상위 공매)
| 컬럼 | 설명 |
|---|---|
| `pbac_no` | 공매번호(PK) |
| `pbac_yy`, `pbac_dgcnt`, `pbac_tncnt` | 공매 연도/차수/회차 |
| `cstm_sgn`, `snar_sgn`, `cargo_tpcd` | 세관/창고/화물유형 FK |
| `pbac_strt_dttm`, `pbac_end_dttm` | 공매 시작/종료 시각 |
| `bid_rstc_yn` | 입찰 제한 여부(Y/N) |
| `elct_bid_eon` | 전자입찰 여부(Y/N) → N이면 일반입찰(현장) 가능성 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 1-6. `auction_item` (하위 물품)
복합 PK: (`pbac_no`, `pbac_srno`, `cmdt_ln_no`)

| 컬럼 | 설명 |
|---|---|
| `pbac_no` | 공매번호(FK) |
| `pbac_srno` | 공매일련번호 |
| `cmdt_ln_no` | 물품라인번호(복합키 구성) |
| `cmdt_nm` | 물품명(원문) |
| `cmdt_qty`, `cmdt_qty_ut_cd` | 수량/수량단위 |
| `cmdt_wght`, `cmdt_wght_ut_cd` | 중량/중량단위 |
| `pbac_prng_prc` | 예정가격/최저입찰가 |
| `atnt_cmdt`, `atnt_cmdt_nm` | 주의물품 여부/표기 |
| `pbac_cond_cn` | 공매 조건 |
| `created_at`, `updated_at` | 생성/수정 시각 |

---

## 2) 분류/검색 테이블

### 2-1. `category` (카테고리 트리)
| 컬럼 | 설명 |
|---|---|
| `category_id` | 카테고리 ID(PK) |
| `parent_id` | 상위 카테고리 ID(self FK) |
| `level` | 레벨(대/중/소/세) |
| `name_ko`, `name_en` | 카테고리 한글/영문명 |
| `is_active` | 활성 여부 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 2-2. `item_classification` (물품 분류 결과)
복합 PK: (`pbac_no`, `pbac_srno`, `cmdt_ln_no`)

| 컬럼 | 설명 |
|---|---|
| `pbac_no`, `pbac_srno`, `cmdt_ln_no` | 대상 물품 키(FK) |
| `category_id` | 분류 결과 카테고리(FK) |
| `model_name`, `model_ver` | 분류 모델명/버전 |
| `confidence` | 신뢰도(0~1) |
| `rationale` | 분류 근거 텍스트 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 2-3. `synonym_dictionary` (동의어/번역 사전)
| 컬럼 | 설명 |
|---|---|
| `dict_id` | 사전 ID(PK) |
| `src_term` | 원본 용어 |
| `norm_term` | 정규화 용어(대표어) |
| `lang` | 언어(EN/KO/MIX) |
| `term_type` | 용어 타입(SYN/TRANSLATION/BRAND/MODEL/CATEGORY_HINT) |
| `weight` | 가중치 |
| `is_active` | 활성 여부 |
| `created_at`, `updated_at` | 생성/수정 시각 |

### 2-4. `item_search_token` (검색 토큰)
복합 PK: (`pbac_no`, `pbac_srno`, `cmdt_ln_no`, `token`)

| 컬럼 | 설명 |
|---|---|
| `pbac_no`, `pbac_srno`, `cmdt_ln_no` | 대상 물품 키(FK) |
| `token` | 검색 토큰 |
| `token_type` | 토큰 유형(RAW/KO/SYN/CATEGORY) |
| `weight` | 검색 랭킹 가중치 |
| `created_at` | 생성 시각 |

### 2-5. `auction_item_image` (물품 이미지)
복합 PK: (`pbac_no`, `pbac_srno`, `cmdt_ln_no`, `image_seq`)

| 컬럼 | 설명 |
|---|---|
| `pbac_no`, `pbac_srno`, `cmdt_ln_no` | 대상 물품 키(FK) |
| `image_seq` | 이미지 순번 |
| `image_url` | 이미지 URL |
| `source_type` | 이미지 수집 출처 |
| `created_at`, `updated_at` | 생성/수정 시각 |


### 2-6. 수집 소스 분리 반영 현황 (중요)
현재 수집기가 3개로 분리된 상황을 기준으로 정리:

- `UNIPASS_LIST_Business.py`: 수입화물 목록 수집
- `UNIPASS_LIST_Personal.py`: 휴대품 목록 수집
- `UNIPASS_Image.py`(또는 이미지 전용 수집기): 이미지 URL/메타 수집

DB 반영 상태:
- 이미지 저장: **있음** (`auction_item_image`)
- 수입화물/휴대품 구분: `cargo_type`(`pbacTrgtCargTpcd`)로 **간접 구분** 가능
- 전자입찰/일반입찰 구분: `auction.elct_bid_eon`으로 **구분 가능**

권장 보강(1차 DDL 후보):
- `auction`에 `collector_source`(BUSINESS/PERSONAL) 또는 동등 필드 추가
- `auction_item_image.source_type` 값 표준화(`UNIPASS_IMAGE`, `LIST_BUSINESS`, `LIST_PERSONAL`)


---

## 3) 재설계 문서 기준 신규(또는 추가 예정) 테이블

> 아래는 `docs/DB_REDESIGN_DISCUSSION.md`에서 합의된 확장안입니다.

### 3-1. `ingestion_run`
| 컬럼 | 설명 |
|---|---|
| `ingestion_run_id` | 수집 실행 ID(PK) |
| `source_name` | 수집 소스 이름 |
| `started_at`, `finished_at` | 실행 시작/종료 시각 |
| `status` | SUCCESS/FAILED/PARTIAL |
| `raw_item_count`, `upsert_count`, `error_count` | 처리 건수 메트릭 |

### 3-2. `raw_auction_payload`
| 컬럼 | 설명 |
|---|---|
| `payload_id` | 페이로드 ID(PK) |
| `ingestion_run_id` | 수집 실행 FK |
| `source_key` | 원문 식별키(pbacNo\|pbacSrno\|cmdtLnNo) |
| `payload_json` | 원문 JSON |
| `payload_hash` | 중복 감지용 해시 |

### 3-3. `auction_item_change_event`
| 컬럼 | 설명 |
|---|---|
| `event_id` | 이벤트 ID(PK) |
| `pbac_no`, `pbac_srno`, `cmdt_ln_no` | 대상 물품 키 |
| `event_type` | PRICE_CHANGED/STATUS_CHANGED/NEW_ITEM/REMOVED_ITEM |
| `before_value_json`, `after_value_json` | 변경 전/후 값 |
| `detected_at` | 변경 감지 시각 |
| `ingestion_run_id` | 수집 실행 FK |

---

## 4) 앱 사용자(`app_user` 성격) - 문서상 제안 테이블

### 4-1. `app_user`
| 컬럼 | 설명 |
|---|---|
| `user_id` | 사용자 ID(PK) |
| `email` | 이메일(UNIQUE) |
| `password_hash` | 로컬 로그인 해시 |
| `status` | ACTIVE/SUSPENDED/DELETED |
| `created_at`, `updated_at`, `last_login_at` | 생성/수정/최종로그인 시각 |

### 4-2. `user_auth_provider`
| 컬럼 | 설명 |
|---|---|
| `user_id` | 사용자 FK |
| `provider` | LOCAL/KAKAO/GOOGLE/APPLE |
| `provider_user_key` | 소셜 고유 식별자 |
| `connected_at` | 연동 시각 |

### 4-3. `user_profile`
| 컬럼 | 설명 |
|---|---|
| `user_id` | 사용자 FK(PK 겸용) |
| `nickname` | 닉네임 |
| `locale`, `timezone` | 지역/시간대 |
| `marketing_opt_in` | 마케팅 수신 동의 |

### 4-4. `user_watchlist_target`
| 컬럼 | 설명 |
|---|---|
| `watch_target_id` | 관심대상 ID(PK) |
| `user_id` | 사용자 FK |
| `target_level` | LOT / ITEM |
| `pbac_no`, `pbac_srno`, `cmdt_ln_no` | 관심대상 식별키 |
| `notify_enabled` | 알림 사용 여부 |
| `memo` | 사용자 메모 |
| `created_at` | 생성 시각 |

---

## 5) 작성/운영 규칙 (권장)

1. 컬럼명은 가급적 `snake_case`, 시간은 `*_at` 규칙 통일
2. 상태값(`status`)은 enum 사전을 테이블별로 일관되게 정의
3. 검색 품질을 위해 원문(`cmdt_nm`)은 보존하고, 정규화명/토큰/동의어는 별도 관리
4. 리네이밍이 필요하면 물리 교체보다 View/alias를 이용한 점진 전환 권장

