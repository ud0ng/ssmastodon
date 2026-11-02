# frozen_string_literal: true

module Game
  # 운영진의 비공개 대결: 컨텐츠 [시작하기]에서 두 캐릭터를 골라 초대하면 두 사람의 DM 으로만 진행한다.
  # 테스트 플레이처럼 state['test'] 를 켜서 소속 점수·보상·전적·순위·하루 횟수에 넣지 않는다 (GameSession.real).
  # 진행중·완료 목록에는 자물쇠와 함께 운영진과 두 참가자에게만 보인다.
  #   두 사람이 모두 [수락]하면 평소처럼 시작한다 (Game::Engine#accept). 연 운영진은 참가자가 아니라 관전한다.
  module PrivateMatch
    module_function

    # 만든 판, 또는 안 되는 까닭(문자열)
    def create!(kind, host:, accounts:)
      return '1:1 컨텐츠만 비공개 대결로 열 수 있습니다.' unless kind.max_opponents == 1 && !kind.event_only?
      return '서로 다른 두 명을 골라 주세요.' unless accounts.size == 2 && accounts.uniq.size == 2

      common = Game::Config.for('common')
      if common['one_game_per_person']
        busy = accounts.find { |account| busy?(account) }
        return Game::Text.render(common['msg_busy'], player: busy) if busy
      end

      session = GameSession.transaction do
        GameSession.create!(kind: kind.key, visibility: 'direct', state: kind.invite_state([]).merge('test' => true, 'private_match' => true, 'host_id' => host.id)).tap do |created|
          accounts.each_with_index { |account, index| created.players.create!(account: account, seat: index) }
        end
      end

      text = Game::Text.render(
        "운영진이 %{game} 비공개 대결을 열었습니다.\n%{player} vs %{opponent}\n\n%{minutes}분 내로 두 사람 모두 [%{accept}] 또는 [%{decline}]로 답해 주세요.\n(비공개 대결은 두 사람과 운영진에게만 보이고, 점수·보상·전적에 들어가지 않습니다)",
        game: kind.display_name, player: accounts.first, opponent: accounts.last,
        accept: common['cmd_accept'], decline: common['cmd_decline'], minutes: common['invite_minutes']
      )
      status = Game::Poster.to_session(session, text)
      session.update!(root_status_id: status.id) if status
      Game::Engine.set_deadline!(session, common['invite_minutes'])
      session
    end

    # 이미 컨텐츠(1:1)를 하고 있다
    def busy?(account)
      GamePlayer.joins(:session).where(account: account, game_sessions: { status: GameSession::OPEN_STATUSES })
                .where.not(game_sessions: { kind: Game::Kinds.group_games.map(&:key) }).exists?
    end
  end
end
