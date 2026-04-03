# frozen_string_literal: true

require "rails_helper"

RSpec.describe Delta::PaperProductsSyncJob do
  it "delegates to PaperCatalog" do
    expect(Delta::PaperCatalog).to receive(:sync_products!).with(symbols: nil)
    described_class.perform_now
  end
end
