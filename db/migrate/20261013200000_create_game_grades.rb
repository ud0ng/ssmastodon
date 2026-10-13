# frozen_string_literal: true

# 마법 수업: 성적표(과목별 등급 기록)와 캐릭터 진도(주문 레벨·수호령)
class CreateGameGrades < ActiveRecord::Migration[8.0]
  def change
    create_table :game_grades, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :game_session, foreign_key: { on_delete: :nullify }
      t.string :subject, null: false
      t.string :grade, null: false
      t.string :mode, null: false, default: 'study'
      t.integer :rank
      t.jsonb :detail, null: false, default: {}
      t.timestamps
    end

    add_column :game_characters, :progress, :jsonb, null: false, default: {}, if_not_exists: true
  end
end
