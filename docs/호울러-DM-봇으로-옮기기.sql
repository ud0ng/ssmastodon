-- 호울러 소문 DM 을 시스템 계정에서 상점 봇 계정으로 옮긴다 (이미 올라간 것). 연회장 문구 툿은 앞 마이그레이션에서 옮겨졌다.
-- 시스템이 올린 DM 은 맨 앞에 받는 사람 태그 줄이 붙어 있어("@ron\n연회장 문구\n\n소문 내용") 그 줄을 빼고 호울러 문구로 시작하는 DM 만 옮긴다.
-- 계정 아이디가 다르면 아래 'system' / 'bot' 을 바꾼다. 맨 아래가 COMMIT 이라 돌리면 바로 반영된다 (개수만 보려면 맨 아래 COMMIT 을 ROLLBACK 으로 바꿔 돌린다).
-- (DB 는 PostgreSQL 11 이상: sha256 내장 함수를 쓴다)
BEGIN;

CREATE TEMP TABLE howler_dms ON COMMIT DROP AS
WITH howler AS (
  SELECT DISTINCT e->>'text' AS text
    FROM game_shop_items i, jsonb_array_elements(i.item_effects) e
   WHERE e->>'kind' = 'rumor' AND COALESCE(e->>'text', '') <> ''
), me AS (
  SELECT (SELECT id FROM accounts WHERE username = 'system' AND domain IS NULL) AS system_id,
         (SELECT id FROM accounts WHERE username = 'bot' AND domain IS NULL) AS bot_id
)
SELECT DISTINCT s.id AS status_id, s.conversation_id, m.account_id AS recipient_id, me.system_id, me.bot_id
  FROM statuses s
  JOIN me ON s.account_id = me.system_id
  JOIN mentions m ON m.status_id = s.id AND m.silent = FALSE
  JOIN howler h ON regexp_replace(s.text, '^(@\S+ *)+\n', '') = h.text
               OR left(regexp_replace(s.text, '^(@\S+ *)+\n', ''), length(h.text) + 2) = h.text || E'\n\n'
 WHERE s.visibility = 3 AND s.local = TRUE AND s.reblog_of_id IS NULL AND s.deleted_at IS NULL AND me.bot_id IS NOT NULL;

SELECT count(*) AS dms_to_move FROM howler_dms;

-- 1) 툿의 보낸 계정, 멘션 알림의 보낸 사람, 툿 개수
UPDATE statuses SET account_id = (SELECT bot_id FROM howler_dms LIMIT 1) WHERE id IN (SELECT status_id FROM howler_dms);

UPDATE notifications SET from_account_id = (SELECT bot_id FROM howler_dms LIMIT 1)
 WHERE activity_type = 'Mention'
   AND from_account_id = (SELECT system_id FROM howler_dms LIMIT 1)
   AND activity_id IN (SELECT m.id FROM mentions m WHERE m.status_id IN (SELECT status_id FROM howler_dms));

UPDATE account_stats SET statuses_count = GREATEST(statuses_count - (SELECT count(*) FROM howler_dms), 0)
 WHERE account_id = (SELECT system_id FROM howler_dms LIMIT 1);
UPDATE account_stats SET statuses_count = statuses_count + (SELECT count(*) FROM howler_dms)
 WHERE account_id = (SELECT bot_id FROM howler_dms LIMIT 1);

-- 2) 웹 채팅(DM 방): 봇과 받는 사람의 방을 만들고, 그 DM 의 대화를 새 방에 붙인다 (방은 참가자 조합마다 하나)
CREATE TEMP TABLE howler_rooms ON COMMIT DROP AS
SELECT d.recipient_id,
       encode(sha256(convert_to(LEAST(d.bot_id, d.recipient_id) || ',' || GREATEST(d.bot_id, d.recipient_id), 'UTF8')), 'hex') AS participant_key,
       d.bot_id,
       min(d.status_id) AS first_status_id,
       max(d.status_id) AS last_status_id
  FROM howler_dms d
 GROUP BY d.recipient_id, d.bot_id;

INSERT INTO dm_rooms (participant_key, member_count, creator_id, root_status_id, last_status_id, created_at, updated_at)
SELECT participant_key, 2, bot_id, first_status_id, last_status_id, now(), now() FROM howler_rooms
ON CONFLICT (participant_key) DO NOTHING;

INSERT INTO dm_room_members (dm_room_id, account_id, created_at, updated_at)
SELECT r.id, a.account_id, now(), now()
  FROM howler_rooms h
  JOIN dm_rooms r ON r.participant_key = h.participant_key
  CROSS JOIN LATERAL (VALUES (h.bot_id), (h.recipient_id)) AS a(account_id)
ON CONFLICT (account_id, dm_room_id) DO NOTHING;

UPDATE conversations c SET dm_room_id = r.id
  FROM howler_dms d
  JOIN howler_rooms h ON h.recipient_id = d.recipient_id
  JOIN dm_rooms r ON r.participant_key = h.participant_key
 WHERE c.id = d.conversation_id;

-- 이미 있던 방이면 마지막 툿 번호를 최신으로 맞춘다
UPDATE dm_rooms r SET last_status_id = h.last_status_id, updated_at = now()
  FROM howler_rooms h
 WHERE r.participant_key = h.participant_key AND (r.last_status_id IS NULL OR r.last_status_id < h.last_status_id);

SELECT count(*) AS moved_dms, (SELECT count(*) FROM howler_rooms) AS rooms FROM howler_dms;

COMMIT;
