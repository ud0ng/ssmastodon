# frozen_string_literal: true

# 게임 한 판. kind: Game::Kinds 의 키 (jellybean 등), status: pending(수락 대기) → active → finished / cancelled
class GameSession < ApplicationRecord
  STATUSES = %w(pending lobby active finished cancelled).freeze
  # 열려 있는 판: 신청·모집(pending) → 대기방(lobby, 모두 준비하면 시작) → 진행(active)
  OPEN_STATUSES = %w(pending lobby active).freeze

  has_many :players, -> { order(:seat) }, class_name: 'GamePlayer', dependent: :destroy, inverse_of: :session
  has_many :house_points, class_name: 'GameHousePoint', dependent: :nullify
  has_many :rewards, class_name: 'GameReward', dependent: :nullify, inverse_of: :session
  has_many :events, class_name: 'GameEvent', dependent: :destroy, inverse_of: :session
  has_many :messages, class_name: 'GameMessage', dependent: :delete_all, inverse_of: :session

  validates :status, inclusion: { in: STATUSES }

  validates :visibility, inclusion: { in: %w(private direct) }

  scope :open, -> { where(status: OPEN_STATUSES) }
  # 지금 있는 컨텐츠의 판만 (없앤 마법 수업·자습 판은 DB 기록으로만 남는다)
  scope :current_kinds, -> { where(kind: Game::Kinds.keys).where("COALESCE(game_sessions.state->>'mode', '') NOT IN ('study', 'class')") }

  # 운영진의 테스트 플레이: 참가자 단체 DM 으로만 진행하고 점수·보상·전적·순위에는 들어가지 않는다 (운영진은 목록에서 자물쇠로 보고 관전)
  scope :real, -> { where("COALESCE(game_sessions.state->>'test', '') <> 'true'") }

  # 웹 전용 컨텐츠(미로·도둑 지도·비밀의 방)는 모집이 끝나 시작한 뒤의 진행·결과를 툿이 아니라 웹 메시지(GameMessage)로만 보낸다.
  # 모집(신청·참가 안내)은 툿이라 앱에서도 보인다.
  def web_channel?
    lobby? || (kind_class&.web? && status != 'pending')
  end

  # 모집이 끝나 대기방에서 준비 중 (아직 시작 전)
  def lobby?
    status == 'lobby'
  end

  def test?
    state.to_h['test'] == true
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  # 없앤 컨텐츠(예전 마법 수업 과목)면 nil
  def kind_class
    Game::Kinds.registry[kind]
  end

  def player_for(account)
    players.find { |player| player.account_id == account.id }
  end

  def opponent_of(player)
    players.find { |other| other.id != player.id }
  end

  # 시간 제한 작업이 아직 유효한지 (새 단계로 넘어가면 예전 작업은 무시)
  def deadline_token
    "#{status}:#{turn}:#{deadline_at&.to_i}"
  end
end
