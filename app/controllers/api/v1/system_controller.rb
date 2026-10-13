# frozen_string_literal: true

# 웹 '시스템' 메뉴: 기숙사 점수, 내 캐릭터·전적, 진행 중인 게임, 최근 게임, 열린 게임 목록
class Api::V1::SystemController < Api::BaseController
  RECENT_LIMIT = 10

  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!

  def show
    common = Game::Config.for('common')
    character = GameCharacter.for(current_account)

    render json: {
      system_acct: Game::System.username,
      house_term: common['house_term'],
      scoring_mode: common['scoring_mode'],
      tournament: tournament_json(GameTournament.current),
      houses: GameHouse.active.map { |house| house_json(house) },
      character: {
        name: character.display_name,
        house_id: character.group_id&.to_s,
        grade: character.grade,
        profile: GameCharacterField.profile.filter_map do |field|
          value = character.profile_value(field)
          { name: field.name, value: value, color: field.choice(value)&.dig('color').presence } if value.present?
        end,
        stats: GameCharacterField.stats.pluck(:name).then { |names| character.stats.slice(*names).merge(character.stats.except(*names)) }.map { |name, value| { name: name, value: value } },
        money: character.money,
        currency: common['currency_name'],
        inventory: Array(character.inventory).map { |item| item.slice('name', 'count', 'note') },
      },
      record: record,
      active: my_players(%w(pending active)).map { |player| game_json(player) },
      recent: my_players(%w(finished)).limit(RECENT_LIMIT).map { |player| game_json(player) },
      games: Game::Kinds.matches.select(&:enabled?).map { |kind| { key: kind.key, name: kind.display_name, command: kind.config['command'], max_opponents: kind.max_opponents } },
      lessons: Game::Lessons.all.select(&:enabled?).map { |kind| { key: kind.key, name: kind.display_name, modes: kind.config['modes'] } },
      lesson_commands: Game::Lessons.config.slice('cmd_study', 'cmd_class', 'cmd_join', 'cmd_report').transform_keys { |key| key.delete_prefix('cmd_') },
      report: report,
      commands: common.slice('cmd_accept', 'cmd_decline', 'cmd_forfeit', 'cmd_points', 'cmd_record').transform_keys { |key| key.delete_prefix('cmd_') },
    }
  end

  private

  def tournament_json(tournament)
    return if tournament.nil?

    {
      id: tournament.id.to_s,
      name: tournament.name,
      status: tournament.status,
      reward: tournament.reward,
      winner_house_id: tournament.winner_house_id&.to_s,
      wins: tournament.house_wins.map { |house, count| { house_id: house.id.to_s, wins: count } },
      rounds: (1..tournament.rounds).map do |round|
        {
          name: tournament.round_name(round),
          matches: tournament.round_matches(round).map { |match| match_json(match) },
        }
      end,
    }
  end

  def match_json(match)
    {
      id: match.id.to_s,
      status: match.status,
      kind_name: match.kind_name,
      scheduled_at: match.scheduled_at&.iso8601,
      winner_acct: match.winner&.acct,
      status_id: match.session && (match.session.last_status_id || match.session.root_status_id)&.to_s,
      session_id: match.session&.id&.to_s,
      players: match.players.map do |account|
        character = GameCharacter.for(account)
        { acct: account.acct, name: character.display_name, house_id: character.group_id&.to_s }
      end,
    }
  end

  # 성적표: 과목별 가장 좋은 등급, 주문 레벨, 수호령, 이번 학기 기여 점수
  def report
    character = GameCharacter.for(current_account)
    grades = GameGrade.where(account: current_account).group_by(&:subject)
    {
      subjects: Game::Lessons.all.map do |kind|
        list = grades.fetch(kind.key, [])
        { key: kind.key, name: kind.display_name, best: GameGrade.best(list.map(&:grade)), count: list.size }
      end,
      spells: (character.progress['spells'] || {}).map { |spell, level| { name: spell, level: level } },
      patronus: character.progress['patronus'],
      points: GameHousePoint.where(account: current_account).sum(:amount),
    }
  end

  def house_json(house)
    { id: house.id.to_s, name: house.name, emoji: house.emoji, color: house.color, total: house.total }
  end

  def record
    results = GamePlayer.joins(:session).where(account: current_account, game_sessions: { status: 'finished' }).group(:result).count
    { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i }
  end

  def my_players(statuses)
    GamePlayer.joins(:session)
              .where(account: current_account, game_sessions: { status: statuses })
              .includes(session: { players: :account })
              .order('game_sessions.updated_at DESC')
  end

  def game_json(player)
    session = player.session
    opponents = session.players.reject { |other| other.id == player.id }

    {
      id: session.id.to_s,
      kind: session.kind,
      name: session.kind_class.display_name,
      status: session.status,
      result: player.result,
      turn: session.turn,
      deadline_at: session.deadline_at&.iso8601,
      finished_at: session.finished_at&.iso8601,
      opponents: opponents.map { |other| { name: other.name, acct: other.account.acct } },
      status_id: (session.last_status_id || session.root_status_id)&.to_s,
    }
  end
end
