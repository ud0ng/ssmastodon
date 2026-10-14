# frozen_string_literal: true

module Game
  # 게임 종류 목록. 새 게임은 Game::Kinds::<이름> 을 만들고 여기에 넣는다.
  module Kinds
    module_function

    def registry
      {
        'jellybean' => Game::Kinds::Jellybean,
        'gobstones' => Game::Kinds::Gobstones,
        'duel' => Game::Kinds::Duel,
        'potion' => Game::Kinds::Potion,
        'quidditch' => Game::Kinds::Quidditch,
        # 웹 전용
        'maze' => Game::Web::Maze,
        'marauders_map' => Game::Web::MaraudersMap,
        # 마법 수업
        'levitation' => Game::Lessons::Levitation,
        'transfiguration' => Game::Lessons::Transfiguration,
        'flying' => Game::Lessons::Flying,
        'practice' => Game::Lessons::Practice,
        # 서버 이벤트
        'secret_chamber' => Game::Events::SecretChamber,
      }
    end

    def keys
      registry.keys
    end

    def fetch(key)
      registry.fetch(key)
    end

    def all
      registry.values
    end

    # 신청해서 하는 컨텐츠 (마법 수업·서버 이벤트 제외)
    def matches
      all.reject { |kind| kind.lesson? || kind.event? }
    end

    # 1:1 대결
    def duels
      matches.select { |kind| kind.max_opponents == 1 }
    end

    # 여럿이 하는 컨텐츠 (퀴디치 팀전, 미로, 도둑 지도)
    def group_games
      matches.select { |kind| kind.max_opponents > 1 }
    end

    # 서버 이벤트 (비밀의방 등)
    def events
      all.select(&:event?)
    end

    # 이 명령어로 시작하는 켜진 게임
    def by_command(command)
      matches.find { |kind| kind.enabled? && kind.config['command'] == command }
    end

    # 명령어는 같지만 꺼져 있는 게임 (안내용)
    def disabled_by_command(command)
      matches.find { |kind| !kind.enabled? && kind.config['command'] == command }
    end
  end
end
