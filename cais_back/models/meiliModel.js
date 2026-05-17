/*
models/meiliModel.js
Meilisearch 기반 검색 + 자동완성
*/
const { client, INDEX_NAME } = require('../config/meili');

const index = () => client.index(INDEX_NAME);

// ── 카테고리 ID → 하위 포함 필터 문자열 생성 ─────────────────────────────
const pool = require('../config/db');

async function buildCategoryFilter(categoryId) {
  if (!categoryId) return null;
  const [rows] = await pool.query(`
    SELECT category_id FROM category
    WHERE category_id = ?
       OR parent_id = ?
       OR parent_id IN (SELECT category_id FROM category WHERE parent_id = ?)
  `, [categoryId, categoryId, categoryId]);
  const ids = rows.map(r => r.category_id);
  if (!ids.length) return null;
  return ids.map(id => `categoryId = ${id}`).join(' OR ');
}

// ── 검색 ────────────────────────────────────────────────────────────────────
exports.search = async ({ keyword, categoryId, cstmSgn, page = 1, limit = 20 }) => {
  const offset = (page - 1) * limit;
  const filters = [];

  const catFilter = await buildCategoryFilter(categoryId);
  if (catFilter) filters.push(`(${catFilter})`);
  if (cstmSgn) {
    // Meilisearch 필터 문자열에 직접 보간되므로 허용 문자만 검증
    if (!/^[\w\-]{1,20}$/.test(cstmSgn)) {
      throw new Error(`유효하지 않은 cstmSgn 값입니다: ${cstmSgn}`);
    }
    filters.push(`cstmSgn = "${cstmSgn}"`);
  }

  const result = await index().search(keyword || '', {
    offset,
    limit,
    filter: filters.length ? filters.join(' AND ') : undefined,
    sort: keyword ? undefined : ['pbacStrtDttm:desc'],
    attributesToRetrieve: [
      'id', 'pbacNo', 'pbacSrno', 'cmdtLnNo',
      'cmdtNm', 'pbacPrngPrc', 'pbacStrtDttm', 'pbacEndDttm',
      'cstmSgn', 'cstmName', 'categoryId', 'categoryName',
      'thumbnailUrl', 'status',
    ],
  });

  return result.hits;
};

// ── 자동완성 ─────────────────────────────────────────────────────────────────
exports.autocomplete = async (q) => {
  if (!q || q.trim().length < 1) return [];

  const result = await index().searchForFacetValues({
    facetName: 'categoryName',
    facetQuery: q,
    limit: 5,
  }).catch(() => null);

  // searchForFacetValues는 카테고리에만 적용. 물품명 자동완성은 일반 검색으로
  const hits = await index().search(q, {
    limit: 8,
    attributesToRetrieve: ['cmdtNm'],
    attributesToSearchOn: ['cmdtNm', 'tokens'],
  });

  // 중복 제거 후 물품명 반환
  const seen = new Set();
  const suggestions = [];
  for (const hit of hits.hits) {
    const name = hit.cmdtNm;
    if (name && !seen.has(name)) {
      seen.add(name);
      suggestions.push(name);
    }
  }
  return suggestions.slice(0, 8);
};
