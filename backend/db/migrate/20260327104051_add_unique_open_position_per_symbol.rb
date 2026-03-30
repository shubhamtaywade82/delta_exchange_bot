class AddUniqueOpenPositionPerSymbol < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE UNIQUE INDEX index_positions_on_symbol_when_open
        ON positions (symbol)
        WHERE status = 'open'
    SQL
  end

  def down
    remove_index :positions, name: :index_positions_on_symbol_when_open
  end
end
