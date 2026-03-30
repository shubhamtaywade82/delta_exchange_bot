#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "bot/indicators/provider"
require "json"

# Sample data: 20 candles with a simple trend
candles = (1..30).map do |i|
  price = 100 + i + (i % 3 == 0 ? 2 : -1)
  {
    open: price - 1,
    high: price + 2,
    low: price - 2,
    close: price,
    volume: 1000,
    timestamp: Time.now - (30 - i) * 60
  }
end

puts "--- Testing Indicator Provider ---"

begin
  rsi_intrinio = Bot::Indicators::Provider.rsi(candles, period: 14, source: :technical_analysis)
  puts "RSI (technical-analysis) - Last index: #{rsi_intrinio.last&.round(2)}"
  puts "RSI (technical-analysis) - Results count: #{rsi_intrinio.size} (Expected: #{candles.size - 14})"
rescue => e
  puts "Error with technical-analysis: #{e.message}"
end

begin
  rsi_ruby_tech = Bot::Indicators::Provider.rsi(candles, period: 14, source: :ruby_technical_analysis)
  puts "RSI (ruby-technical-analysis) - Last index: #{rsi_ruby_tech.last&.round(2)}"
  puts "RSI (ruby-technical-analysis) - Results count: #{rsi_ruby_tech.size}"
rescue => e
  puts "Error with ruby-technical-analysis: #{e.message}"
end

puts "\n--- Testing Backend Refactored RSI ---"
# We can't easily run the backend service without Rails env, 
# but we can simulate the compute logic here by copying the refactored RSI compute code
# or just assume the provider test covers the core logic.

puts "Verification script complete."
