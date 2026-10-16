# frozen_string_literal: true

module Game
  module Kinds
    # 마법결투: 매 턴 두 사람이 몰래(DM) 주문을 고르고 동시에 공개한다. 가위바위보 상성.
    #   공격(스투페파이) > 무장해제 > 방어 > 공격
    # HP 를 먼저 0 으로 만들면 승리, 최대 턴이 지나면 HP 가 많은 쪽 승리 (같으면 무승부).
    # 필살기: 한 판에 한 번 [주문/필살] — 이기면 피해 2배, 지면 내가 2배 피해.
    class Duel < Base
      KEY = 'duel'

      SPELLS = %w(attack disarm defend).freeze
      # 이 주문이 이기는 상대
      BEATS = { 'attack' => 'disarm', 'disarm' => 'defend', 'defend' => 'attack' }.freeze

      FIELDS = (base_fields(name: '마법결투', command: '결투', points_win: 10, points_draw: 3) + [
        F.new(key: 'hp', type: :integer, default: 3, group: 'rules', label: '시작 HP'),
        F.new(key: 'max_turns', type: :integer, default: 10, group: 'rules', label: '최대 턴'),
        F.new(key: 'damage', type: :integer, default: 1, group: 'rules', label: '이겼을 때 피해'),
        F.new(key: 'special_multiplier', type: :integer, default: 2, group: 'rules', label: '필살기 배수'),
        F.new(key: 'cmd_attack', type: :string, default: '공격', group: 'commands', label: '공격 명령어'),
        F.new(key: 'cmd_disarm', type: :string, default: '무장해제', group: 'commands', label: '무장해제 명령어'),
        F.new(key: 'cmd_defend', type: :string, default: '방어', group: 'commands', label: '방어 명령어'),
        F.new(key: 'cmd_special', type: :string, default: '필살', group: 'commands', label: '필살기', hint: '[공격/필살] 처럼 주문 뒤에 붙인다'),
        F.new(key: 'spell_attack', type: :string, default: '스투페파이', group: 'spells', label: '공격 주문 이름'),
        F.new(key: 'spell_disarm', type: :string, default: '엑스펠리아르무스', group: 'spells', label: '무장해제 주문 이름'),
        F.new(key: 'spell_defend', type: :string, default: '프로테고', group: 'spells', label: '방어 주문 이름'),
        F.new(key: 'msg_start', type: :text, group: 'messages', label: '시작',
              default: "%{game} 시작! 각자 %{hp}의 체력으로 시작합니다.\n\n매 턴 시스템 계정이 보내는 DM에 주문을 답해 주세요.\n모든 인원이 주문을 고르면 결과가 공개됩니다."),
        F.new(key: 'msg_ask', type: :text, group: 'messages', label: 'DM: 주문 고르기',
              default: "%{turn}턴 | 주문을 골라 주세요.\n[%{attack}] · [%{disarm}] · [%{defend}]\n%{special_hint}"),
        F.new(key: 'msg_special_hint', type: :text, group: 'messages', label: 'DM: 필살기 남음',
              default: "[%{attack}/%{special}]{은는} 피해를 %{multiplier}배로 줄 수 있습니다."),
        F.new(key: 'msg_chosen', type: :text, group: 'messages', label: 'DM: 선택 확인', default: "주문을 정했습니다. 상대를 기다립니다."),
        F.new(key: 'msg_round', type: :text, group: 'messages', label: '턴 결과',
              default: "%{turn}턴\n\n%{player_a} vs %{player_b}\n[%{choice_a}]　　[%{choice_b}]\n%{outcome}"),
        F.new(key: 'msg_round_win', type: :text, group: 'messages', label: '한쪽 승리', default: "%{winner}의 주문이 통했습니다.\n💔 %{loser} -%{damage}"),
        F.new(key: 'msg_round_backfire', type: :text, group: 'messages', label: '필살기 역풍', default: "%{winner}의 주문이 통했습니다.\n필살기가 빗나간 %{loser}{은는} 피해를 입었습니다.\n💔 %{loser} -%{damage}"),
        F.new(key: 'msg_round_tie', type: :text, group: 'messages', label: '같은 주문', default: "같은 주문이 맞부딪혀 흩어졌습니다. 피해는 없습니다."),
        F.new(key: 'msg_both_fail', type: :text, group: 'messages', label: '둘 다 시간 초과', default: "두 사람 모두 주문을 고르지 않았습니다. 피해는 없습니다."),
        F.new(key: 'msg_fail', type: :text, group: 'messages', label: '주문 실패 (시간 초과)', default: "시간 초과"),
        F.new(key: 'msg_win', type: :text, group: 'messages', label: '승리', default: "%{loser}{이가} 쓰러졌습니다.\n%{winner}의 승리입니다."),
        F.new(key: 'msg_limit', type: :text, group: 'messages', label: '최대 턴', default: "최대 턴(%{turns}턴)이 지났습니다.\n%{outcome}"),
        F.new(key: 'msg_draw', type: :text, group: 'messages', label: '무승부', default: '남은 HP가 같아 무승부입니다.'),
      ]).freeze

      def self.continues_on_timeout?
        true
      end

      def start!
        hp = config['hp'].to_i.clamp(1, 20)
        state.merge!('hp' => players.to_h { |player| [player.seat.to_s, hp] }, 'choices' => {}, 'special_used' => {})
        session.update!(turn: 1)
        post(render(config['msg_start'], hp: hp))
        ask_all!
      end

      def handle(player, command, args, status)
        spell = SPELLS.find { |key| config["cmd_#{key}"] == command }
        return false if spell.nil?
        return true unless require_dm!(player, status)

        special = args.first == config['cmd_special'] && !state['special_used'][player.seat.to_s]
        state['choices'][player.seat.to_s] = { 'spell' => spell, 'special' => special }
        session.save!
        dm(player, render(config['msg_chosen']))
        resolve! if state['choices'].size == players.size
        true
      end

      # 시간 안에 고르지 않은 사람은 '주문 실패'로 이번 턴을 진행한다
      def timeout!
        resolve!
      end

      def max_turns
        config['max_turns'].to_i
      end

      def card_data
        {
          'hp' => state['hp'] || {},
          'max_hp' => config['hp'].to_i,
          'max_turns' => config['max_turns'].to_i,
          'special_used' => state['special_used'] || {},
          'chosen' => (state['choices'] || {}).keys,
          'last_round' => state['last_round'],
        }
      end

      # 주문은 DM 으로 고른다. 필살기는 아직 안 쓴 사람만.
      def card_actions
        seats = players.map(&:seat)
        spells = SPELLS.map { |key| Game::Card.action(config["cmd_#{key}"], seats: seats, dm: true) }
        fresh = seats.reject { |seat| state.dig('special_used', seat.to_s) }
        specials = fresh.empty? ? [] : SPELLS.map { |key| Game::Card.action("#{config["cmd_#{key}"]}/#{config['cmd_special']}", label: "#{config["cmd_#{key}"]}·#{config['cmd_special']}", seats: fresh, dm: true, style: 'secondary', row: 2) }
        spells + specials
      end

      private

      def ask_all!
        players.each do |player|
          special_hint = state['special_used'][player.seat.to_s] ? '' : render(config['msg_special_hint'], attack: config['cmd_attack'], special: config['cmd_special'], multiplier: config['special_multiplier'])
          dm(player, render(config['msg_ask'], turn: session.turn, special_hint: special_hint, **spell_names))
        end
        wait_for_turn!
      end

      def spell_names
        SPELLS.each_with_object({}) do |key, names|
          names[key.to_sym] = config["cmd_#{key}"]
          names[:"spell_#{key}"] = config["spell_#{key}"]
        end
      end

      def choice_label(choice)
        return render(config['msg_fail']) if choice.nil?

        label = config["cmd_#{choice['spell']}"]
        choice['special'] ? "#{label}·#{config['cmd_special']}" : label
      end

      def resolve!
        a, b = players
        choice_a = state['choices'][a.seat.to_s]
        choice_b = state['choices'][b.seat.to_s]
        [[a, choice_a], [b, choice_b]].each { |player, choice| state['special_used'][player.seat.to_s] = true if choice&.dig('special') }

        winner, loser, winning_choice, losing_choice = duel(a, choice_a, b, choice_b)
        outcome = if choice_a.nil? && choice_b.nil?
                    render(config['msg_both_fail'])
                  elsif winner.nil?
                    render(config['msg_round_tie'])
                  else
                    damage = config['damage'].to_i
                    multiplier = config['special_multiplier'].to_i
                    backfire = losing_choice&.dig('special') && !winning_choice&.dig('special')
                    damage *= multiplier if winning_choice&.dig('special') || backfire
                    state['hp'][loser.seat.to_s] = [state['hp'][loser.seat.to_s] - damage, 0].max
                    render(config[backfire ? 'msg_round_backfire' : 'msg_round_win'], winner: winner, loser: loser, damage: damage)
                  end

        round_text = render(config['msg_round'], turn: session.turn, player_a: a, player_b: b,
                                                 choice_a: choice_label(choice_a), choice_b: choice_label(choice_b), outcome: outcome)
        state['last_round'] = {
          'choices' => { a.seat.to_s => choice_label(choice_a), b.seat.to_s => choice_label(choice_b) },
          'winner_seat' => winner&.seat,
        }
        state['choices'] = {}

        fallen = players.find { |player| state['hp'][player.seat.to_s].zero? }
        if fallen
          survivor = session.opponent_of(fallen)
          finish!(winner: survivor, message: "#{round_text}\n\n#{render(config['msg_win'], winner: survivor, loser: fallen)}")
        elsif session.turn >= config['max_turns'].to_i
          finish_by_hp!(round_text)
        else
          post(round_text)
          session.update!(turn: session.turn + 1)
          ask_all!
        end
      end

      # [이긴 사람, 진 사람, 이긴 선택, 진 선택] (무승부면 nil)
      def duel(a, choice_a, b, choice_b)
        return if choice_a.nil? && choice_b.nil?
        return [a, b, choice_a, choice_b] if choice_b.nil?
        return [b, a, choice_b, choice_a] if choice_a.nil?
        return if choice_a['spell'] == choice_b['spell']

        BEATS[choice_a['spell']] == choice_b['spell'] ? [a, b, choice_a, choice_b] : [b, a, choice_b, choice_a]
      end

      def finish_by_hp!(round_text)
        a, b = players
        hp_a = state['hp'][a.seat.to_s]
        hp_b = state['hp'][b.seat.to_s]
        if hp_a == hp_b
          finish!(draw: true, message: "#{round_text}\n\n#{render(config['msg_limit'], turns: session.turn, outcome: render(config['msg_draw']))}")
        else
          winner = hp_a > hp_b ? a : b
          finish!(winner: winner, message: "#{round_text}\n\n#{render(config['msg_limit'], turns: session.turn, outcome: render(config['msg_win'], winner: winner, loser: session.opponent_of(winner)))}")
        end
      end
    end
  end
end
