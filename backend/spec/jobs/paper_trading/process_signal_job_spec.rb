# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::ProcessSignalJob do
  let(:wallet) { create(:paper_wallet, cash_balance: "100_000", equity: "100_000") }
  let(:product) { create(:paper_product_snapshot, product_id: 27, symbol: "BTCUSD", risk_unit_per_contract: "0.001") }
  let(:signal) do
    create(:paper_trading_signal,
      paper_wallet: wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      risk_pct: "0.01",
      status: "pending")
  end

  before do
    PaperTrading::RedisStore.set_ltp(product.product_id, BigDecimal("50100"), symbol: product.symbol)
  end

  it "fills signal and creates order and fill" do
    expect do
      described_class.perform_now(signal.id)
    end.to change(PaperOrder, :count).by(1).and change(PaperFill, :count).by(1)
    expect(signal.reload.status).to eq("filled")
  end

  it "is idempotent on replay" do
    described_class.perform_now(signal.id)
    expect { described_class.perform_now(signal.id) }.not_to change(PaperFill, :count)
  end

  it "rejects when quantity below 1" do
    tiny_wallet = create(:paper_wallet, cash_balance: "5", equity: "5")
    bad = create(:paper_trading_signal,
      paper_wallet: tiny_wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      risk_pct: "0.0001",
      status: "pending")
    described_class.perform_now(bad.id)
    expect(bad.reload.status).to eq("rejected")
  end

  it "handles two signals on same wallet without duplicate client_order_id" do
    sig2 = create(:paper_trading_signal,
      paper_wallet: wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      risk_pct: "0.001",
      status: "pending")

    threads = [signal, sig2].map do |s|
      Thread.new { described_class.perform_now(s.id) }
    end
    threads.each(&:join)

    expect(PaperOrder.count).to eq(2)
    expect(PaperOrder.distinct.pluck(:client_order_id).size).to eq(2)
  end
end
