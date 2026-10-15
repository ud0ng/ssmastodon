# frozen_string_literal: true

# 시즌 (캐릭터 관리 > 소속): 이름·기간, 진행 중 / 끝. 시즌을 끝내면 최종 점수를 남기고 소속 점수를 0부터 다시 센다.
# 툿 보상 (컨텐츠 설정 > 설정 > 재화 설정): 캐릭터마다 지금까지 받은 횟수와 그때의 기준
class CreateGameSeasons < ActiveRecord::Migration[8.0]
  def change
    create_table :game_seasons do |t|
      t.string :name, null: false
      t.date :starts_on
      t.date :ends_on
      t.string :status, null: false, default: 'running' # running / finished
      t.jsonb :results, null: false, default: [] # 끝날 때 소속별 최종 점수 [{ house_id, name, total }]
      t.datetime :finished_at
      t.timestamps
    end

    add_column :game_characters, :toot_reward_units, :integer, null: false, default: 0
    add_column :game_characters, :toot_reward_basis, :string, null: false, default: ''
  end
end
