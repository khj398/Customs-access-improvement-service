/* server.js - 서버 진입점 */
require('dotenv').config();
const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`CAIS API 서버 실행: http://localhost:${PORT}`);
});
