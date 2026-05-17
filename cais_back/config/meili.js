/*
config/meili.js
Meilisearch 클라이언트 싱글톤
*/
const { Meilisearch: MeiliSearch } = require('meilisearch');

const client = new MeiliSearch({
  host: process.env.MEILI_HOST || 'http://localhost:7700',
  apiKey: process.env.MEILI_MASTER_KEY || 'cais-search-key',
});

const INDEX_NAME = 'auction_items';

module.exports = { client, INDEX_NAME };
