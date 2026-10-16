# frozen_string_literal: true

# 웹 '시스템' 메뉴: 기숙사 점수, 내 캐릭터·전적, 진행 중인 게임, 최근 게임, 열린 게임 목록
class Api::V1::SystemController < Api::BaseController
  include RoutingHelper

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
        avatar: full_asset_url(current_account.avatar_static_url),
        house_id: character.group_id&.to_s,
        profile: profile_tags(character),
        stats: character_stats(character),
        money: character.money,
        currency: common['currency_name'],
        inventory: Array(character.inventory).map { |item| item.slice('name', 'count', 'note') },
      },
      record: record,
      active: my_players(%w(pending active)).map { |player| game_json(player) },
      recent: my_players(%w(finished)).limit(RECENT_LIMIT).map { |player| game_json(player) },
      games: Game::Kinds.matches.select(&:enabled?).map { |kind| { key: kind.key, name: kind.display_name, command: kind.config['command'], max_opponents: kind.max_opponents } },
      catalog: catalog,
      commands: common.slice('cmd_accept', 'cmd_decline', 'cmd_forfeit', 'cmd_points', 'cmd_record').transform_keys { |key| key.delete_prefix('cmd_') },
    }
  end

  private

  # 스탯 값과 상태 수치(수식 계산): [{ name, value }]
  def character_stats(character)
    base = GameCharacterField.base_stats.to_a
    base.map { |field| { name: field.name, value: character.stat_value(field).to_s } } +
      GameCharacterField.statuses.map { |field| { name: field.name, value: (character.status_value(field, base) || '-').to_s } }
  end

  # 내 캐릭터 칩: 점수 기준이 아닌 쪽 소속(기숙사 또는 진영)
  def profile_tags(character)
    groups = [character.house, character.faction].compact.reject { |group| group.id == character.group_id }
    groups.map { |group| { name: group.category, value: group.label, color: group.color.presence } }
  end

  # 컨텐츠 고르기 (묶음별): 진행 중 판 수, 내가 하는 중인지
  def catalog
    open = GameSession.current_kinds.where(status: %w(pending active)).group(:kind).count
    mine = GamePlayer.joins(:session).where(account: current_account, game_sessions: { status: %w(pending active) }).distinct.pluck('game_sessions.kind')
    kinds = Game::Kinds.all.select(&:enabled?)
    Game::Guide::GROUPS.map do |group|
      {
        key: group,
        games: kinds.select { |kind| Game::Guide.group_of(kind) == group }.map do |kind|
          { key: kind.key, name: kind.display_name, summary: Game::Guide.for(kind)[:summary], open: open.fetch(kind.key, 0), mine: mine.include?(kind.key) }
        end,
      }
    end
  end

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

  def house_json(house)
    { id: house.id.to_s, name: house.name, emoji: house.emoji, color: house.color, total: house.total }
  end

  def record
    results = GamePlayer.joins(:session).where(account: current_account, game_sessions: { status: 'finished' }).group(:result).count
    { win: results['win'].to_i, lose: results['lose'].to_i, draw: results['draw'].to_i }
  end

  def my_players(statuses)
    GamePlayer.joins(:session).merge(GameSession.current_kinds)
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
