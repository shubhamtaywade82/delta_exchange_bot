# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaperTrading::FillApplier do
  before { allow(Finance::UsdInrRate).to receive(:current).and_return(85) }

  let(:wallet) { create(:paper_wallet, seed_inr: BigDecimal("50000")) }
  let(:product) do
    create(:paper_product_snapshot,
      symbol: "SOLUSD",
      contract_value: BigDecimal("1"),
      risk_unit_per_contract: BigDecimal("1"),
      default_leverage: 10,
      raw_metadata: { "taker_fee_rate" => "0.0005" })
  end
  let(:signal) { create(:paper_trading_signal, paper_wallet: wallet, product_id: product.product_id) }

  def create_order(side:, size:)
    create(:paper_order,
      paper_wallet: wallet,
      paper_product_snapshot: product,
      paper_trading_signal: signal,
      side: side,
      size: size)
  end

  describe "long fill lifecycle" do
    it "handles scale in, partial exit, and full exit in INR ledger terms" do
      entry = described_class.new(order: create_order(side: "buy", size: 3), wallet: wallet, product: product)
      entry.call(price: BigDecimal("80"), size: 3, leverage: 10)

      add_on = described_class.new(order: create_order(side: "buy", size: 2), wallet: wallet, product: product)
      add_on.call(price: BigDecimal("77.5"), size: 2, leverage: 10)

      partial_exit = described_class.new(order: create_order(side: "sell", size: 2), wallet: wallet, product: product)
      partial_exit.call(price: BigDecimal("82"), size: 2, leverage: 10)

      full_exit = described_class.new(order: create_order(side: "sell", size: 3), wallet: wallet, product: product)
      full_exit.call(price: BigDecimal("84"), size: 3, leverage: 10)

      wallet.reload
      expect(wallet.balance_inr).to eq(BigDecimal("51744.33"))
      expect(wallet.used_margin_inr).to eq(BigDecimal("0"))
      expect(wallet.available_inr).to eq(BigDecimal("51744.33"))
      expect(wallet.realized_pnl_inr).to eq(BigDecimal("1785"))

      total_fees = wallet.paper_wallet_ledger_entries.where(entry_type: "commission").sum(:amount_inr)
      expect(total_fees).to eq(BigDecimal("40.67"))
    end

    it "charges maker fee rate when liquidity is maker" do
      product.update!(raw_metadata: { "taker_fee_rate" => "0.0005", "maker_fee_rate" => "0.0002" })
      maker_entry = described_class.new(order: create_order(side: "buy", size: 1), wallet: wallet, product: product)

      maker_entry.call(price: BigDecimal("80"), size: 1, leverage: 10, liquidity: :maker)

      commission = wallet.reload.paper_wallet_ledger_entries.where(entry_type: "commission").sum(:amount_inr)
      expect(commission).to eq(BigDecimal("1.60"))
    end

    it "fills buy at ask and sell at bid when market snapshot is provided" do
      buy = described_class.new(order: create_order(side: "buy", size: 1), wallet: wallet, product: product)
      buy.call(price: BigDecimal("100"), size: 1, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 101, depth: 100 })

      sell = described_class.new(order: create_order(side: "sell", size: 1), wallet: wallet, product: product)
      sell.call(price: BigDecimal("100"), size: 1, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 101, depth: 100 })

      prices = PaperFill.order(:id).last(2).map(&:price)
      expect(prices.first).to eq(BigDecimal("101"))
      expect(prices.last).to eq(BigDecimal("99"))
    end

    it "applies larger slippage for larger order size" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_SLIPPAGE_BPS").and_return("0")
      allow(ENV).to receive(:[]).with("PAPER_IMPACT_BPS").and_return("20")

      small = described_class.new(order: create_order(side: "buy", size: 1), wallet: wallet, product: product)
      small.call(price: BigDecimal("100"), size: 1, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 100, depth: 100 })

      large = described_class.new(order: create_order(side: "buy", size: 10), wallet: wallet, product: product)
      large.call(price: BigDecimal("100"), size: 10, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 100, depth: 100 })

      small_price, large_price = PaperFill.order(:id).last(2).map(&:price)
      expect(large_price).to be > small_price
    end

    it "caps slippage for extreme order size" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_SLIPPAGE_BPS").and_return("0")
      allow(ENV).to receive(:[]).with("PAPER_IMPACT_BPS").and_return("200")
      allow(ENV).to receive(:[]).with("PAPER_MAX_SLIPPAGE_BPS").and_return("50")
      allow(ENV).to receive(:[]).with("PAPER_MAX_LEVERAGE_CAP").and_return("100000")

      huge_wallet = create(:paper_wallet, seed_inr: BigDecimal("2_000_000"))
      huge_signal = create(:paper_trading_signal, paper_wallet: huge_wallet, product_id: product.product_id)
      huge_order = create(:paper_order,
        paper_wallet: huge_wallet,
        paper_product_snapshot: product,
        paper_trading_signal: huge_signal,
        side: "buy",
        size: 1000)

      applier = described_class.new(order: huge_order, wallet: huge_wallet, product: product)
      applier.call(price: BigDecimal("100"), size: 1000, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 100, depth: 10 })

      expect(PaperFill.last.price).to eq(BigDecimal("100.5"))
    end

    it "supports latency distribution around configured delay" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAPER_EXEC_DELAY_MS").and_return("50")
      allow(ENV).to receive(:[]).with("PAPER_EXEC_DELAY_STD_MS").and_return("15")
      allow_any_instance_of(described_class).to receive(:sleep)

      applier = described_class.new(order: create_order(side: "buy", size: 1), wallet: wallet, product: product)
      applier.call(price: BigDecimal("100"), size: 1, leverage: 10, liquidity: :taker, market_snapshot: { bid: 99, ask: 100, depth: 100 })

      expect(applier).to have_received(:sleep)
    end
  end
end
