# frozen_string_literal: true

module Game
  # 아이템 사용 중 웹과 시스템 DM 명령어가 같이 쓰는 부분 (호울러: 내용을 모든 서버원에게 DM 소문으로)
  module ItemUse
    class Error < StandardError; end

    MAX_RUMOR = 200

    module_function

    def clean_rumor(text)
      text.to_s.strip.delete('@＠')[0, MAX_RUMOR]
    end

    # 누가 보냈는지 밝히지 않고 등록된 모든 캐릭터에게 한 사람씩 DM (그룹 DM 으로 묶지 않는다). 보낸 사람 수를 돌려준다.
    # 트랜잭션 안에서 부르지 말 것: 멘션 알림 작업이 커밋 전에 돌면 알림이 빠진다.
    def broadcast_rumor!(text)
      sent = 0
      GameCharacter.eligible_accounts.to_a.each do |account|
        sent += 1 if Game::Poster.post("호울러가 울려 퍼집니다!\n#{text}", mentions: [account], thread: nil, visibility: 'direct')
      rescue => e
        Rails.logger.warn { "howler to #{account.username} failed: #{e.class} #{e.message}" }
      end
      sent
    end

    # 시스템 계정에 DM 으로 보낸 [사용/호울러/내용] (모바일). 아이템을 하나 쓰고 소문을 낸다. 문구를 돌려준다.
    def howler!(account, item, text)
      raise Error, "#{item.name}은(는) 사용할 수 없는 아이템입니다." unless item.usable

      rumor = clean_rumor(text)
      raise Error, '소문 내용을 적어 주세요. 예: [사용/호울러/소문 내용]' if rumor.blank?

      Game::Wallet.apply!([{ account: account, items: { item.name => -1 } }], kind: 'use', detail: "#{item.name} (소문)", actor: 'system')
      sent = broadcast_rumor!(rumor)
      Game::Gift.announce(account, command: ['사용', item.name, rumor], system: true)
      "호울러가 호그와트 전체에 울려 퍼졌습니다. (#{sent}명에게 전달)"
    end
  end
end
