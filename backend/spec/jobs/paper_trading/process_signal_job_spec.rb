# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::ProcessSignalJob do
  include ActiveJob::TestHelper

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
    clear_enqueued_jobs

    expect do
      described_class.perform_now(signal.id)
    end.to change(PaperOrder, :count).by(1)
      .and change(PaperFill, :count).by(1)
      .and have_enqueued_job(PaperTrading::RepriceWalletJob).with(wallet.id)
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

  it "rejects when fill-price margin exceeds available margin" do
    clear_enqueued_jobs

    tiny_wallet = create(:paper_wallet, seed_inr: BigDecimal("1000"))
    pricey_signal = create(:paper_trading_signal,
      paper_wallet: tiny_wallet,
      product_id: product.product_id,
      side: "buy",
      entry_price: "50000",
      stop_price: "49000",
      max_loss_inr: BigDecimal("50_000"),
      status: "pending")

    allow(PaperTrading::RrPositionSizer).to receive(:compute!).and_return(
      PaperTrading::RrPositionSizer::Result.new(final_contracts: 1)
    )

    described_class.perform_now(pricey_signal.id)

    expect(pricey_signal.reload.status).to eq("rejected")
    expect(pricey_signal.rejection_reason).to eq("insufficient available margin for fill price")
    expect(PaperOrder.where(paper_trading_signal: pricey_signal)).to be_empty
    expect(enqueued_jobs).to be_empty
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

  it "marks signal rejected when fill application raises insufficient margin in transaction" do
    clear_enqueued_jobs

    allow_any_instance_of(PaperTrading::FillApplicator).to receive(:call)
      .and_raise(PaperTrading::PositionManager::InsufficientMarginError, "late affordability failure")

    described_class.perform_now(signal.id)

    expect(signal.reload.status).to eq("rejected")
    expect(signal.rejection_reason).to include("late affordability failure")
    expect(PaperOrder.where(paper_trading_signal: signal)).to be_empty
    expect(enqueued_jobs).to be_empty
  end
end
