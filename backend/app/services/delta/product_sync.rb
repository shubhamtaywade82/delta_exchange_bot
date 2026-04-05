# frozen_string_literal: true

module Delta
  # Syncs Delta /v2/products fields required by paper execution.
  class ProductSync
    def self.sync!(symbols: nil)
      PaperCatalog.sync_products!(symbols: symbols)
    end
  end
end
