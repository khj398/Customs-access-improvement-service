/*
controllers/fileController.js
파일 업로드 컨트롤러 (로컬 디스크)
*/

exports.uploadImage = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: '파일이 없습니다' });
    // 로컬 정적 경로로 URL 반환
    const url = `/uploads/${req.file.filename}`;
    res.status(201).json({ url });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '업로드 실패' });
  }
};

exports.getImage = async (req, res) => {
  // 정적 파일 서빙은 app.js의 express.static이 처리
  res.status(404).json({ error: '직접 조회는 지원하지 않습니다' });
};
