# 0. DATABASE 생성

CREATE DATABASE studyshare default CHARACTER SET UTF8;

# 1. 기존 트리거&테이블 제거

## 트리거가 이미 있다면 먼저 삭제

DROP TRIGGER IF EXISTS increase_like_count;
DROP TRIGGER IF EXISTS decrease_like_count;
DROP TRIGGER IF EXISTS increase_comment_count;
DROP TRIGGER IF EXISTS decrease_comment_count;

## FK 의존 순서대로 테이블 삭제

DROP TABLE IF EXISTS study_time;
DROP TABLE IF EXISTS comment;
DROP TABLE IF EXISTS likes;
DROP TABLE IF EXISTS image;
DROP TABLE IF EXISTS feed;
DROP TABLE IF EXISTS user;

# 2. FK 없이 기본 테이블 생성

-- 1) user
CREATE TABLE user (
  userId INT AUTO_INCREMENT PRIMARY KEY,
  userName VARCHAR(255) NOT NULL,
  userEmail VARCHAR(255) NOT NULL UNIQUE,
  userPassword VARCHAR(255) NOT NULL,
  profileImageId INT NULL
);

-- 2) feed
CREATE TABLE feed (
  feedId INT AUTO_INCREMENT PRIMARY KEY,
  userId INT NOT NULL,
  studyDate DATE NOT NULL,
  totalStudyTime INT NOT NULL DEFAULT 0,
  content LONGTEXT NOT NULL,
  likeCount INT NOT NULL DEFAULT 0,
  commentCount INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_feed_userId (userId),
  INDEX idx_feed_created_at (created_at)
);

-- 3) image
CREATE TABLE image (
  imageId INT AUTO_INCREMENT PRIMARY KEY,
  feedId INT NULL,
  userId INT NULL,
  imagePath VARCHAR(500) NOT NULL,
  INDEX idx_image_feedId (feedId),
  INDEX idx_image_userId (userId)
);

-- 4) likes
CREATE TABLE likes (
  likeId INT AUTO_INCREMENT PRIMARY KEY,
  feedId INT NOT NULL,
  userId INT NOT NULL,
  UNIQUE KEY unique_feed_user (feedId, userId),
  INDEX idx_likes_feedId (feedId),
  INDEX idx_likes_userId (userId)
);

-- 5) comment
CREATE TABLE comment (
  commentId INT AUTO_INCREMENT PRIMARY KEY,
  feedId INT NOT NULL,
  userId INT NOT NULL,
  commentContent TEXT NOT NULL,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_comment_feedId (feedId),
  INDEX idx_comment_userId (userId),
  INDEX idx_comment_createdAt (createdAt)
);

-- 6) study_time
CREATE TABLE study_time (
  studyTimeId INT AUTO_INCREMENT PRIMARY KEY,
  feedId INT NOT NULL,
  subject VARCHAR(255) NOT NULL,
  studyTime INT NOT NULL DEFAULT 0,
  INDEX idx_study_feedId (feedId)
);

# 3. 외래키 제약 추가

-- 1) user.profileImageId → image.imageId
ALTER TABLE user
  ADD CONSTRAINT fk_user_profile_image
  FOREIGN KEY (profileImageId)
  REFERENCES image(imageId)
  ON DELETE SET NULL;

-- 2) feed.userId → user.userId
ALTER TABLE feed
  ADD CONSTRAINT fk_feed_user
  FOREIGN KEY (userId)
  REFERENCES user(userId)
  ON DELETE CASCADE;

-- 3) image.feedId → feed.feedId
ALTER TABLE image
  ADD CONSTRAINT fk_image_feed
  FOREIGN KEY (feedId)
  REFERENCES feed(feedId)
  ON DELETE SET NULL;

-- 4) image.userId → user.userId
ALTER TABLE image
  ADD CONSTRAINT fk_image_user
  FOREIGN KEY (userId)
  REFERENCES user(userId)
  ON DELETE SET NULL;

-- 5) likes.feedId → feed.feedId
ALTER TABLE likes
  ADD CONSTRAINT fk_likes_feed
  FOREIGN KEY (feedId)
  REFERENCES feed(feedId)
  ON DELETE CASCADE;

-- 6) likes.userId → user.userId
ALTER TABLE likes
  ADD CONSTRAINT fk_likes_user
  FOREIGN KEY (userId)
  REFERENCES user(userId)
  ON DELETE CASCADE;

-- 7) comment.feedId → feed.feedId
ALTER TABLE comment
  ADD CONSTRAINT fk_comment_feed
  FOREIGN KEY (feedId)
  REFERENCES feed(feedId)
  ON DELETE CASCADE;

-- 8) comment.userId → user.userId
ALTER TABLE comment
  ADD CONSTRAINT fk_comment_user
  FOREIGN KEY (userId)
  REFERENCES user(userId)
  ON DELETE CASCADE;

-- 9) study_time.feedId → feed.feedId
ALTER TABLE study_time
  ADD CONSTRAINT fk_study_feed
  FOREIGN KEY (feedId)
  REFERENCES feed(feedId)
  ON DELETE CASCADE;

# 4. CommentCount trigger 추가

CREATE TRIGGER increase_like_count
AFTER INSERT ON likes
FOR EACH ROW
UPDATE feed
SET likeCount = likeCount + 1
WHERE feedId = NEW.feedId;

CREATE TRIGGER decrease_like_count
AFTER DELETE ON likes
FOR EACH ROW
UPDATE feed
SET likeCount = likeCount - 1
WHERE feedId = OLD.feedId;

CREATE TRIGGER increase_comment_count
AFTER INSERT ON comment
FOR EACH ROW
UPDATE feed
SET commentCount = commentCount + 1
WHERE feedId = NEW.feedId;

CREATE TRIGGER decrease_comment_count
AFTER DELETE ON comment
FOR EACH ROW
UPDATE feed
SET commentCount = commentCount - 1
WHERE feedId = OLD.feedId;

# 테스트 데이터 셋 입력

-- ========================================
-- 1️⃣ 모든 테이블 데이터 삭제 (초기화)
-- ========================================

SET FOREIGN_KEY_CHECKS = 0;

DELETE FROM likes;
DELETE FROM comment;
DELETE FROM study_time;
DELETE FROM image;
DELETE FROM feed;
DELETE FROM user;

SET FOREIGN_KEY_CHECKS = 1;

ALTER TABLE user AUTO_INCREMENT = 1;
ALTER TABLE feed AUTO_INCREMENT = 1;
ALTER TABLE comment AUTO_INCREMENT = 1;
ALTER TABLE image AUTO_INCREMENT = 1;
ALTER TABLE study_time AUTO_INCREMENT = 1;
ALTER TABLE likes AUTO_INCREMENT = 1;

-- ========================================
-- 2️⃣ 프로필 이미지 먼저 생성! (3개)
-- ========================================

INSERT INTO image (feedId, userId, imagePath) VALUES
(NULL, NULL, 'storage\\2026\\0119\\1.png'),    -- imageId: 1
(NULL, NULL, 'storage\\2026\\0119\\2.png'),    -- imageId: 2
(NULL, NULL, 'storage\\2026\\0119\\3.png');    -- imageId: 3

-- ========================================
-- 3️⃣ 이제 User 삽입 (프로필 이미지 참조 가능)
-- ========================================

INSERT INTO user (userName, userEmail, userPassword, profileImageId) VALUES
('김철수', 'kim@email.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIJZAgcg7b3XeKeUxWdeS86E36gZvWUm', 1),
('이영희', 'lee@email.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIJZAgcg7b3XeKeUxWdeS86E36gZvWUm', 2),
('박민수', 'park@email.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIJZAgcg7b3XeKeUxWdeS86E36gZvWUm', 3);

-- ========================================
-- 4️⃣ 프로필 이미지의 userId 업데이트
-- ========================================

UPDATE image SET userId = 1 WHERE imageId = 1;
UPDATE image SET userId = 2 WHERE imageId = 2;
UPDATE image SET userId = 3 WHERE imageId = 3;

-- ========================================
-- 5️⃣ 피드 데이터 (30개)
-- ========================================

INSERT INTO feed (userId, studyDate, totalStudyTime, content, created_at) VALUES
(1, '2025-11-01', 150, '오늘 주특공부 열심히 했다! 미적분은 정말 어렵지만 재미있었다.', '2025-11-01 18:32:55'),
(1, '2025-11-03', 180, '영어 100개 단어를 외웠다. 계속해야겠다.', '2025-11-03 18:32:55'),
(2, '2025-11-05', 120, '과학 실험 준비 완료. 화학 반응 정말 신기하다!', '2025-11-05 18:32:55'),
(3, '2025-11-07', 200, '아침 일찍 시작해서 공부했다. 확실히 효율이 좋다!', '2025-11-07 18:32:55'),
(1, '2025-11-10', 90, '피곤하지만 공부는 계속해야한다!', '2025-11-10 18:32:55'),
(2, '2025-11-12', 160, '과학 실험 재미있게 하고 있네!', '2025-11-12 18:32:55'),
(3, '2025-11-15', 140, '오늘 시간이 부족했지만 최선을 다했다!', '2025-11-15 18:32:55'),
(1, '2025-11-18', 175, '이 정도면 정말 훌륭한 적을 경험했다!', '2025-11-18 18:32:55'),
(2, '2025-11-20', 145, '노력하는 모습이 정말 좋다!', '2025-11-20 18:32:55'),
(3, '2025-11-22', 155, '역사는 재미있게 배웠다 오래 기억될 듯', '2025-11-22 18:32:55'),
(1, '2025-12-01', 165, '12월도 화이팅! 열심히 공부해야지', '2025-12-01 18:32:55'),
(2, '2025-12-03', 170, '겨울방학 열심히 준비하는 중!', '2025-12-03 18:32:55'),
(3, '2025-12-05', 185, '공부하는 시간이 가장 행복해!', '2025-12-05 18:32:55'),
(1, '2025-12-08', 130, '오늘도 화이팅', '2025-12-08 18:32:55'),
(2, '2025-12-10', 195, '최고의 하루를 보냈어!', '2025-12-10 18:32:55'),
(3, '2025-12-12', 150, '공부 중독자 되어가는 중', '2025-12-12 18:32:55'),
(1, '2025-12-15', 160, '겨울방학 시작 전 최종 정리 중!', '2025-12-15 18:32:55'),
(2, '2025-12-18', 175, '공부의 즐거움을 느끼고 있어!', '2025-12-18 18:32:55'),
(3, '2025-12-20', 145, '연말 최고의 공부 멘토링!', '2025-12-20 18:32:55'),
(1, '2025-12-25', 200, '크리스마스도 공부를!', '2025-12-25 18:32:55'),
(2, '2026-01-01', 170, '새해 새마음으로 공부 시작!', '2026-01-01 18:32:55'),
(3, '2026-01-03', 185, '1월도 열심히!', '2026-01-03 18:32:55'),
(1, '2026-01-05', 155, '공부가 제일 재미있어!', '2026-01-05 18:32:55'),
(2, '2026-01-07', 180, '우리 함께 공부하자!', '2026-01-07 18:32:55'),
(3, '2026-01-10', 165, '수학 정말 열심히 공부 중', '2026-01-10 18:32:55'),
(1, '2026-01-12', 175, '국어도 재미있어!', '2026-01-12 18:32:55'),
(2, '2026-01-14', 190, '영어 완전 마스터 중!', '2026-01-14 18:32:55'),
(3, '2026-01-15', 210, '시험 준비 열심히 중', '2026-01-15 18:32:55'),
(1, '2026-01-17', 160, '공부 스트리크 30일!', '2026-01-17 18:32:55'),
(2, '2026-01-19', 180, '계속 이렇게 열심히 하자!', '2026-01-19 18:32:55');

-- ========================================
-- 6️⃣ 공부 시간 데이터
-- ========================================

INSERT INTO study_time (feedId, subject, studyTime) VALUES
(1, '수학', 90), (1, '국어', 60),
(2, '영어', 120), (2, '사회', 60),
(3, '과학', 80), (3, '수학', 40),
(4, '수학', 100), (4, '영어', 100),
(5, '국어', 90),
(6, '영어', 80), (6, '수학', 80),
(7, '수학', 70), (7, '국어', 70),
(8, '수학', 90), (8, '영어', 85),
(9, '사회', 90), (9, '국어', 55),
(10, '역사', 160),
(11, '수학', 90), (11, '영어', 75),
(12, '국어', 85), (12, '과학', 85),
(13, '사회', 95), (13, '수학', 90),
(14, '영어', 130),
(15, '수학', 100), (15, '영어', 95),
(16, '국어', 80), (16, '과학', 70),
(17, '수학', 85), (17, '영어', 75),
(18, '사회', 95), (18, '국어', 80),
(19, '과학', 90), (19, '수학', 55),
(20, '수학', 120), (20, '영어', 80),
(21, '국어', 95), (21, '사회', 75),
(22, '수학', 100), (22, '영어', 85),
(23, '과학', 80), (23, '국어', 75),
(24, '영어', 100), (24, '수학', 80),
(25, '수학', 100), (25, '영어', 65),
(26, '국어', 90), (26, '과학', 85),
(27, '영어', 110), (27, '사회', 80),
(28, '수학', 130), (28, '영어', 80),
(29, '국어', 85), (29, '수학', 75),
(30, '수학', 90), (30, '영어', 90);

-- ========================================
-- 7️⃣ 피드 이미지 (Feed마다 1개씩, imageId: 4~33)
-- ========================================

INSERT INTO image (feedId, userId, imagePath) VALUES
(1, 1, 'storage\\2026\\0119\\4.png'),
(2, 1, 'storage\\2026\\0119\\5.png'),
(3, 2, 'storage\\2026\\0119\\6.png'),
(4, 3, 'storage\\2026\\0119\\7.png'),
(5, 1, 'storage\\2026\\0119\\8.png'),
(6, 2, 'storage\\2026\\0119\\9.png'),
(7, 3, 'storage\\2026\\0119\\10.png'),
(8, 1, 'storage\\2026\\0119\\11.png'),
(9, 2, 'storage\\2026\\0119\\12.png'),
(10, 3, 'storage\\2026\\0119\\13.png'),
(11, 1, 'storage\\2026\\0119\\14.png'),
(12, 2, 'storage\\2026\\0119\\15.png'),
(13, 3, 'storage\\2026\\0119\\16.png'),
(14, 1, 'storage\\2026\\0119\\17.png'),
(15, 2, 'storage\\2026\\0119\\18.png'),
(16, 3, 'storage\\2026\\0119\\19.png'),
(17, 1, 'storage\\2026\\0119\\20.png'),
(18, 2, 'storage\\2026\\0119\\21.png'),
(19, 3, 'storage\\2026\\0119\\22.png'),
(20, 1, 'storage\\2026\\0119\\23.png'),
(21, 2, 'storage\\2026\\0119\\24.png'),
(22, 3, 'storage\\2026\\0119\\25.png'),
(23, 1, 'storage\\2026\\0119\\26.png'),
(24, 2, 'storage\\2026\\0119\\27.png'),
(25, 3, 'storage\\2026\\0119\\28.png'),
(26, 1, 'storage\\2026\\0119\\29.png'),
(27, 2, 'storage\\2026\\0119\\30.png'),
(28, 3, 'storage\\2026\\0119\\31.png'),
(29, 1, 'storage\\2026\\0119\\32.png'),
(30, 2, 'storage\\2026\\0119\\33.png');

-- ========================================
-- 8️⃣ 좋아요 데이터 (중복 없음, Feed당 0~5개 서로 다른 사용자)
-- ========================================

DELETE FROM likes;  -- 기존 중복된 좋아요 삭제

INSERT INTO likes (feedId, userId) VALUES
-- Feed 1: 2개
(1, 2), (1, 3),
-- Feed 2: 3개
(2, 1), (2, 2), (2, 3),
-- Feed 3: 2개
(3, 1), (3, 3),
-- Feed 4: 3개 (4-1 중복 제거)
(4, 2), (4, 3), (4, 1),
-- Feed 5: 1개
(5, 2),
-- Feed 6: 3개
(6, 1), (6, 3), (6, 2),
-- Feed 7: 2개
(7, 1), (7, 2),
-- Feed 8: 3개 (중복 제거)
(8, 1), (8, 2), (8, 3),
-- Feed 9: 3개
(9, 1), (9, 2), (9, 3),
-- Feed 10: 3개 (중복 제거)
(10, 1), (10, 2), (10, 3),
-- Feed 11: 2개
(11, 2), (11, 3),
-- Feed 12: 3개
(12, 1), (12, 3), (12, 2),
-- Feed 13: 3개 (중복 제거)
(13, 1), (13, 2), (13, 3),
-- Feed 14: 3개 (중복 제거)
(14, 1), (14, 2), (14, 3),
-- Feed 15: 2개
(15, 1), (15, 3),
-- Feed 16: 3개
(16, 1), (16, 2), (16, 3),
-- Feed 17: 1개
(17, 2),
-- Feed 18: 3개 (중복 제거)
(18, 1), (18, 2), (18, 3),
-- Feed 19: 2개
(19, 1), (19, 3),
-- Feed 20: 3개 (중복 제거)
(20, 1), (20, 2), (20, 3),
-- Feed 21: 3개
(21, 1), (21, 2), (21, 3),
-- Feed 22: 2개
(22, 2), (22, 3),
-- Feed 23: 3개 (중복 제거)
(23, 1), (23, 2), (23, 3),
-- Feed 24: 1개
(24, 3),
-- Feed 25: 3개
(25, 1), (25, 2), (25, 3),
-- Feed 26: 2개
(26, 1), (26, 2),
-- Feed 27: 3개 (중복 제거)
(27, 1), (27, 2), (27, 3),
-- Feed 28: 3개 (중복 제거)
(28, 1), (28, 2), (28, 3),
-- Feed 29: 3개
(29, 1), (29, 2), (29, 3),
-- Feed 30: 2개
(30, 1), (30, 3);

-- ========================================
-- 9️⃣ 댓글 데이터 (각 Feed마다 0~3개)
-- ========================================

INSERT INTO comment (feedId, userId, commentContent, createdAt) VALUES
(1, 2, '오우! 수학 공부 열심히 하네!', '2025-11-01 14:52:08'),
(1, 3, '미적분은 어렵지만 다할 수 있어!', '2025-11-01 14:52:08'),
(2, 1, '영어 단어 100개는 정말 대단한데?', '2025-11-03 18:32:55'),
(2, 3, '영어를 계속 공부하는 게 확실이다!', '2025-11-03 18:32:55'),
(2, 1, '정말 열심히 하고 있네!', '2025-11-03 18:32:55'),
(3, 1, '과학 실험 정말 신기하네!', '2025-11-05 18:32:55'),
(4, 2, '아침 시간이 공부하니 정말 좋은데', '2025-11-07 18:32:55'),
(4, 3, '이 정도면 정말 영실히 하는 것 같다', '2025-11-07 18:32:55'),
(4, 1, '효율이 정말 좋다!', '2025-11-07 18:32:55'),
(5, 2, '피곤해도 화이팅!', '2025-11-10 18:32:55'),
(7, 1, '오늘도 힘내 화이팅!', '2025-11-15 18:32:55'),
(7, 3, '정말 열심히 하는군!', '2025-11-15 18:32:55'),
(8, 2, '이 정도면 정말 훌륭할 적을 경험했다!', '2025-11-18 18:32:55'),
(9, 1, '노력하는 모습이 정말 보기 좋아!', '2025-11-20 18:32:55'),
(9, 3, '화이팅!', '2025-11-20 18:32:55'),
(11, 2, '12월도 화이팅!', '2025-12-01 18:32:55'),
(11, 3, '공부 열심히 해봐!', '2025-12-01 18:32:55'),
(11, 1, '너무 멋진데!', '2025-12-01 18:32:55'),
(12, 3, '겨울방학도 화이팅!', '2025-12-03 18:32:55'),
(13, 1, '공부하는 시간이 정말 행복한군!', '2025-12-05 18:32:55'),
(13, 2, '우리도 함께 해야겠다!', '2025-12-05 18:32:55'),
(14, 3, '오늘도 화이팅!', '2025-12-08 18:32:55'),
(15, 1, '최고의 하루를 보냈군!', '2025-12-10 18:32:55'),
(15, 2, '공부 정말 열심히 하네!', '2025-12-10 18:32:55'),
(15, 3, '너무 멋진데!', '2025-12-10 18:32:55'),
(17, 1, '겨울방학 최종 정리 화이팅!', '2025-12-15 18:32:55'),
(17, 3, '너도 화이팅!', '2025-12-15 18:32:55'),
(18, 2, '공부의 즐거움 정말 멋진데!', '2025-12-18 18:32:55'),
(19, 1, '연말 최고의 공부 멘토링이다!', '2025-12-20 18:32:55'),
(19, 2, '정말 훌륭한 모습!', '2025-12-20 18:32:55'),
(19, 3, '계속 파이팅!', '2025-12-20 18:32:55'),
(20, 1, '크리스마스도 공부한다 정신 좋네!', '2025-12-25 18:32:55'),
(20, 2, '정말 대단하다!', '2025-12-25 18:32:55'),
(21, 3, '새해 새마음 화이팅!', '2026-01-01 18:32:55'),
(22, 1, '1월도 열심히 해봐!', '2026-01-03 18:32:55'),
(22, 2, '정말 멋진데!', '2026-01-03 18:32:55'),
(22, 3, '함께 화이팅!', '2026-01-03 18:32:55'),
(24, 1, '공부가 제일 재미있다니!', '2026-01-05 18:32:55'),
(24, 2, '맞아! 우리도 함께!', '2026-01-05 18:32:55'),
(25, 3, '정말 최고의 공부 팀!', '2026-01-07 18:32:55'),
(26, 1, '수학 정말 열심히 공부 중이네!', '2026-01-10 18:32:55'),
(26, 2, '정말 멋진 노력!', '2026-01-10 18:32:55'),
(26, 3, '계속 화이팅!', '2026-01-10 18:32:55'),
(27, 1, '국어도 재미있다니!', '2026-01-12 18:32:55'),
(27, 2, '정말 대단한 공부 능력!', '2026-01-12 18:32:55'),
(28, 3, '영어 완전 마스터 중이네!', '2026-01-14 18:32:55'),
(29, 1, '시험 준비 화이팅!', '2026-01-15 18:32:55'),
(29, 2, '정말 멋진 준비!', '2026-01-15 18:32:55'),
(29, 3, '계속 최고로!', '2026-01-15 18:32:55'),
(30, 1, '공부 스트리크 30일 축하!', '2026-01-17 18:32:55'),
(30, 2, '정말 대단한 기록!', '2026-01-17 18:32:55');