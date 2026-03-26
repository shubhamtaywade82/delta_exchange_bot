FactoryBot.define do
  factory :symbol_config do
    symbol { "MyString" }
    leverage { 1 }
    enabled { false }
  end
end
