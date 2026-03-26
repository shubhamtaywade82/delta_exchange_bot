class CreateTradingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :trading_sessions do |t|
      t.string :strategy
      t.string :status
      t.decimal :capital
      t.integer :leverage
      t.datetime :started_at
      t.datetime :stopped_at

      t.timestamps
    end
  end
end
