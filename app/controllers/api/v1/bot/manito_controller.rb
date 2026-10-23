# frozen_string_literal: true

# 자동봇 [마니또/단어/캐릭터] : 상점봇을 태그한 추측을 서버가 판정한다 (Game::Manito.guess!)
#   POST /api/v1/bot/manito/guess  { acct: 추측하는 사람, word: 단어, target: 캐릭터 이름이나 아이디 }
#   → { message: 상점봇이 답할 문구 }   안 되면 422 { error: 문구 }
class Api::V1::Bot::ManitoController < Api::V1::Bot::BaseController
  rescue_from Game::Manito::Error do |error|
    render json: { error: error.message, code: 'manito_failed' }, status: 422
  end

  def guess
    guesser = find_character(params[:acct])
    return render json: { error: 'Character not found', code: 'not_found' }, status: 404 if guesser.nil?

    accused = find_character(params[:target])
    raise Game::Manito::Error, "'#{params[:target]}' 캐릭터를 찾을 수 없습니다." if accused.nil?
    raise Game::Manito::Error, "형식: [#{Game::Manito.command}/단어/캐릭터]" if params[:word].to_s.strip.empty?

    render json: { message: Game::Manito.guess!(guesser.account, params[:word].to_s.strip, accused.account) }
  end
end
