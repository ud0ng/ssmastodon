# frozen_string_literal: true

namespace :commu do
  desc '모든 툿(DM 포함)을 지웁니다. 계정·설정·재화·게임 전적은 그대로. 확인 없이는 개수만 보여 줍니다 (CONFIRM=yes 를 붙이면 실제로 지움)'
  task reset_statuses: :environment do
    counts = {
      '툿' => Status.unscoped.count,
      '알림' => Notification.count,
      '대화방(DM) 묶음' => Conversation.count,
      '진행 중인 컨텐츠' => GameSession.open.count,
    }
    counts.each { |name, count| puts "#{name}: #{count}" }

    unless ENV['CONFIRM'] == 'yes'
      puts "\n지우지 않았습니다. 정말 지우려면 CONFIRM=yes 를 붙여 다시 실행하세요. (되돌릴 수 없으니 먼저 DB 백업)"
      next
    end

    Commu::StatusReset.call
    puts "\n툿을 모두 지웠습니다. 서버를 다시 시작하지 않아도 됩니다."
  end
end
