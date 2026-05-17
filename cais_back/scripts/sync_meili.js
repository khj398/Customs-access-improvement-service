/*
scripts/sync_meili.js
MySQL auction_item 데이터를 Meilisearch에 동기화

실행: node cais_back/scripts/sync_meili.js
*/
require('dotenv').config();
const pool   = require('../config/db');
const { client, INDEX_NAME } = require('../config/meili');

async function setup() {
  const index = client.index(INDEX_NAME);

  // 검색 가능 필드
  await index.updateSearchableAttributes([
    'cmdtNm',
    'categoryName',
    'cstmName',
    'tokens',
  ]);

  // 필터 가능 필드 (카테고리·세관 필터용)
  await index.updateFilterableAttributes([
    'categoryId',
    'cstmSgn',
    'status',
  ]);

  // 정렬 가능 필드
  await index.updateSortableAttributes([
    'pbacEndDttm',
    'pbacPrngPrc',
    'pbacStrtDttm',
  ]);

  // 자동완성용 typo tolerance
  await index.updateTypoTolerance({
    enabled: true,
    minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 },
  });

  console.log('✅ Meilisearch 인덱스 설정 완료');
}

async function fetchItems() {
  const [rows] = await pool.query(`
    SELECT
      ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
      ai.cmdt_nm AS cmdtNm,
      ai.pbac_prng_prc AS pbacPrngPrc,
      a.pbac_strt_dttm AS pbacStrtDttm,
      a.pbac_end_dttm  AS pbacEndDttm,
      a.cstm_sgn AS cstmSgn,
      co.cstm_name AS cstmName,
      c.category_id AS categoryId,
      c.name_ko AS categoryName,
      (
        SELECT GROUP_CONCAT(DISTINCT ist.token ORDER BY ist.token SEPARATOR ' ')
        FROM item_search_token ist
        WHERE ist.pbac_no = ai.pbac_no
          AND ist.pbac_srno = ai.pbac_srno
          AND ist.cmdt_ln_no = ai.cmdt_ln_no
      ) AS tokens,
      (
        SELECT aii.image_url
        FROM auction_item_image aii
        WHERE aii.pbac_no = ai.pbac_no
          AND aii.pbac_srno = ai.pbac_srno
          AND aii.cmdt_ln_no = ai.cmdt_ln_no
        ORDER BY aii.image_seq
        LIMIT 1
      ) AS thumbnailUrl
    FROM auction_item ai
    JOIN auction a ON ai.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN item_classification ic
      ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
  `);
  return rows;
}

function makeId(row) {
  // Meilisearch primaryKey: 영숫자+언더스코어만 허용
  return `${row.pbac_no}_${row.pbac_srno}_${row.cmdt_ln_no}`;
}

async function sync() {
  console.log('🔄 Meilisearch 동기화 시작...');
  await setup();

  const rows = await fetchItems();
  console.log(`📦 총 ${rows.length}개 물품 로드`);

  const docs = rows.map(r => ({
    id:           makeId(r),
    pbacNo:       r.pbac_no,
    pbacSrno:     r.pbac_srno,
    cmdtLnNo:     r.cmdt_ln_no,
    cmdtNm:       r.cmdtNm || '',
    pbacPrngPrc:  Number(r.pbacPrngPrc) || 0,
    pbacStrtDttm: r.pbacStrtDttm ? new Date(r.pbacStrtDttm).toISOString() : null,
    pbacEndDttm:  r.pbacEndDttm  ? new Date(r.pbacEndDttm).toISOString()  : null,
    cstmSgn:      r.cstmSgn || '',
    cstmName:     r.cstmName || '',
    categoryId:   r.categoryId || null,
    categoryName: r.categoryName || '기타',
    tokens:       r.tokens || '',
    thumbnailUrl: r.thumbnailUrl || null,
    status:       r.pbacEndDttm && new Date(r.pbacEndDttm) > new Date() ? '진행중' : '마감',
  }));

  // 배치 1000개씩 업로드
  const BATCH = 1000;
  for (let i = 0; i < docs.length; i += BATCH) {
    const batch = docs.slice(i, i + BATCH);
    await client.index(INDEX_NAME).addDocuments(batch, { primaryKey: 'id' });
    console.log(`  ↑ ${Math.min(i + BATCH, docs.length)}/${docs.length} 업로드`);
  }

  console.log('✅ 동기화 완료!');
  process.exit(0);
}

sync().catch(err => {
  console.error('❌ 동기화 실패:', err);
  process.exit(1);
});
