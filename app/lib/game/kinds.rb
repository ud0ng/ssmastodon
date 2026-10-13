# frozen_string_literal: true

module Game
  # 게임 종류 목록. 새 게임은 Game::Kinds::<이름> 을 만들고 여기에 넣는다.
  module Kinds
    module_function

    def registry
      { 'jellybean' => Game::Kinds::Jellybean }
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

    # 이 명령어로 시작하는 켜진 게임
    def by_command(command)
      all.find { |kind| kind.enabled? && kind.config['command'] == command }
    end

    # 명령어는 같지만 꺼져 있는 게임 (안내용)
    def disabled_by_command(command)
      all.find { |kind| !kind.enabled? && kind.config['command'] == command }
    end
  end
end
