# frozen_string_literal: true

module Game
  # 이벤트(비행 대결·미로·도둑 지도·비밀의 방)가 시작되거나 끝났을 때 앱에서도 알 수 있게 시스템 계정이 알린다
  # (이벤트 방과 진행은 웹 전용이라 앱에는 안 보인다).
  #   모집하기로 연 이벤트   참가자를 멘션한 툿 (모집 툿과 같은 공개 범위)
  #   초대하기·테스트 플레이  초대받은 사람에게만 DM
  # 문구는 컨텐츠 설정 > 이벤트 문구 (msg_event_started / msg_event_finished)
  module EventNotice
    DEFAULTS = {
      started: '%{game}{이가} 시작됐어요! 이벤트를 확인하세요.',
      finished: '%{game}{이가} 끝났어요! 이벤트를 확인하세요.',
    }.freeze

    module_function

    # 이벤트가 시작됐다(진행 중으로 바뀜) / 끝났다(finished). 이벤트가 아닌 판은 무시
    def call(session, event)
      return unless session.state['mode'] == 'event' && Game::Kinds.group_games.map(&:key).include?(session.kind)
      return if Game::System.account.nil?

      kind = session.kind_class
      invited = Array(session.state['invited']).map(&:to_i)
      text = Game::Text.render(kind.config["msg_event_#{event}"].presence || DEFAULTS.fetch(event), game: kind.display_name)

      if invited.any?
        Account.where(id: invited).find_each { |account| Game::Poster.post(text, mentions: [account], thread: nil, visibility: 'direct') }
      else
        accounts = session.players.map(&:account)
        Game::Poster.post(text, mentions: accounts, thread: nil, visibility: 'private') if accounts.any?
      end
    rescue StandardError => e
      Rails.logger.warn { "event notice failed for session #{session.id}: #{e.class} #{e.message}" }
    end
  end
end
