# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::ProcessSignalJob do
  let(:wallet) { create(:paper_wallet) }
  let(:product) { create(:paper_product_snapshot, product_id: 27, symbol: "BTCUSD", risk_unit_per_contract: "0.001") }
  let(:signal) do
    create(:paper_trading_signal,
      paper_wallet: wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      max_loss_inr: BigDecimal("50_000"),
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
    tiny_wallet = create(:paper_wallet, seed_inr: BigDecimal("1"))
    bad = create(:paper_trading_signal,
      paper_wallet: tiny_wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      max_loss_inr: BigDecimal("5000"),
      status: "pending")
    described_class.perform_now(bad.id)
    expect(bad.reload.status).to eq("rejected")
  end

  it "passes wallet available_inr into the RR sizer" do
    wallet.reload.recompute_from_ledger!
    expected_available = wallet.reload.available_inr.to_d

    allow(PaperTrading::RrPositionSizer).to receive(:compute!).and_wrap_original do |method, **kwargs|
      expect(kwargs[:available_margin_inr]).to eq(expected_available)
      method.call(**kwargs)
    end

    described_class.perform_now(signal.id)
  end

  it "handles two signals on same wallet without duplicate client_order_id" do
    sig2 = create(:paper_trading_signal,
      paper_wallet: wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      max_loss_inr: BigDecimal("10_000"),
      status: "pending")

    threads = [ signal, sig2 ].map do |s|
      Thread.new { described_class.perform_now(s.id) }
    end
    threads.each(&:join)

    expect(PaperOrder.count).to eq(2)
    expect(PaperOrder.distinct.pluck(:client_order_id).size).to eq(2)
  end
end
