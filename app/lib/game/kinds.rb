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
        'flying' => Game::Kinds::Flying,
        # 웹 전용
        'maze' => Game::Web::Maze,
        'marauders_map' => Game::Web::MaraudersMap,
        'secret_chamber' => Game::Web::SecretChamber,
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

    # 컨텐츠 전부 (예전에는 서버 이벤트를 뺐다)
    def matches
      all
    end

    # 1:1 대결
    def duels
      matches.select { |kind| kind.max_opponents == 1 }
    end

    # 여럿이 하는 컨텐츠 (퀴디치 팀전, 비행 대결, 미로, 도둑 지도, 비밀의 방)
    def group_games
      matches.select { |kind| kind.max_opponents > 1 }
    end

    # 이 명령어로 시작하는 켜진 게임
    def by_command(command)
      matches.reject(&:event_only?).find { |kind| kind.enabled? && kind.config['command'] == command }
    end

    # 명령어는 같지만 꺼져 있는 게임 (안내용)
    def disabled_by_command(command)
      matches.reject(&:event_only?).find { |kind| !kind.enabled? && kind.config['command'] == command }
    end
  end
end
