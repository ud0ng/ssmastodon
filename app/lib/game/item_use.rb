# frozen_string_literal: true

module Game
  # 아이템 사용 중 웹과 시스템 DM 명령어가 같이 쓰는 부분 (소문내기). 사용 규칙은 ItemUse::Runner
  #   사용자가 시스템 계정에 DM [사용/호울러/내용] (웹은 사용 버튼이 대신 보낸다) →
  #   1) 시스템 계정이 아이템에 정해 둔 연회장 문구를 팔로워 공개 툿으로 (announce_howler!)
  #   2) 이어서 시스템 계정이 모든 캐릭터에게 DM 으로 (broadcast_rumor!): 연회장 문구 + 빈 줄 + 내용
  module ItemUse
    class Error < StandardError; end

    MAX_RUMOR = 200

    module_function

    def clean_rumor(text)
      text.to_s.strip.delete('@＠')[0, MAX_RUMOR]
    end

    # 호울러(연회장 문구·소문 DM)를 올리는 계정: 상점 봇 계정(컨텐츠 설정 > 설정 > 상점 계정 아이디), 없으면 시스템 계정.
    # 시스템 계정의 컨텐츠 툿은 웹에서 숨기는데, 호울러는 모두가 봐야 해서 봇 계정으로 올린다
    def howler_account
      Game::Gift.bot_accounts.first || Game::System.account
    end

    # 호울러가 울려 퍼진다: 아이템에 정해 둔 문구를 봇 계정이 팔로워 공개 툿으로 (보낸 사람은 밝히지 않는다)
    def announce_howler!(text)
      Game::Poster.post(text, mentions: [], thread: nil, visibility: 'private', from: howler_account) ? 1 : 0
    rescue => e
      Rails.logger.warn { "howler toot failed: #{e.class} #{e.message}" }
      0
    end

    # 누가 보냈는지 밝히지 않고 등록된 모든 캐릭터에게 한 사람씩 DM (봇 계정으로) (그룹 DM 으로 묶지 않는다). 보낸 사람 수를 돌려준다.
    # 트랜잭션 안에서 부르지 말 것: 멘션 알림 작업이 커밋 전에 돌면 알림이 빠진다.
    def broadcast_rumor!(text, header: nil)
      sent = 0
      GameCharacter.eligible_accounts.to_a.each do |account|
        sent += 1 if Game::Poster.post([header.presence, text].compact.join("\n\n"), mentions: [account], thread: nil, visibility: 'direct', from: howler_account)
      rescue => e
        Rails.logger.warn { "howler to #{account.username} failed: #{e.class} #{e.message}" }
      end
      sent
    end
  end
end
