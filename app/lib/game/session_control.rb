# frozen_string_literal: true

module Game
  # 운영진이 관리 화면에서 진행 중인 컨텐츠를 직접 다루는 일 (오류·멈춘 판 대비)
  #   advance!  지금 단계를 시간이 다 된 것처럼 넘긴다 (멈춘 턴·모집 마감)
  #   cancel!   결과 없이 취소 (점수·보상 없음)
  #   draw!     무승부로 끝냄 (점수·보상 없음)
  #   decide!   고른 사람을 승자로 끝냄 (점수·보상은 평소처럼)
  module SessionControl
    module_function

    # 토너먼트 경기는 토너먼트 화면에서만 판정한다
    def tournament?(session)
      session.state['tournament_match_id'].present?
    end

    def advance!(session)
      session.with_lock do
        next unless session.open?

        if session.status == 'pending' && %w(class event).include?(session.state['mode'])
          session.kind_class.new(session).recruitment_over!
        elsif session.status == 'pending'
          close!(session, 'cancelled', '운영진이 신청을 닫았습니다.')
        else
          session.kind_class.new(session).timeout!
        end
      end
    end

    def cancel!(session)
      session.with_lock do
        close!(session, 'cancelled', '운영진이 이 판을 취소했습니다. 점수와 보상은 없습니다.') if session.open? && !tournament?(session)
      end
    end

    def draw!(session)
      session.with_lock do
        next unless session.open? && !tournament?(session)

        session.players.each { |player| player.update!(result: 'draw') }
        close!(session, 'finished', '운영진이 이 판을 무승부로 끝냈습니다. 점수와 보상은 없습니다.')
      end
    end

    def decide!(session, player)
      session.with_lock do
        next unless session.open? && session.status == 'active' && !tournament?(session) && !session.kind_class.event_only?

        session.kind_class.new(session).send(:finish!, winner: player, message: '운영진이 승자를 정해 판을 끝냈습니다.')
      end
    end

    def close!(session, status, notice)
      session.update!(status: status, finished_at: Time.now.utc, deadline_at: nil)
      Game::Poster.to_session(session, notice)
    end
  end
end
