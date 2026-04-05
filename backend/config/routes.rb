Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  namespace :api do
    get "dashboard" => "dashboard#index"
    post "dashboard/close_position" => "dashboard#close_position"
    post "dashboard/paper_risk_override" => "dashboard#paper_risk_override"
    resources :positions, only: [:index]
    resources :trades, only: [:index]
    resources :signals, only: [:index]
    # Dots in setting keys (e.g. strategy.timeframes.confirm) must not be parsed as :id + format.
    get "settings", to: "settings#index"
    get "settings/changes", to: "settings#changes"
    # Glob so dotted keys (strategy.timeframes.confirm) are not split into :id + :format.
    patch "settings/*id", to: "settings#update", format: false
    resources :trading_sessions, only: [:index, :create, :destroy]
    get "strategy_status" => "strategy_status#index"
    get "wallet"          => "wallet#index"
    get "analysis_dashboard" => "analysis_dashboard#index"
    get "symbols/:symbol/order_blocks" => "order_blocks#show"

    # New catalog and watchlist
    resources :products, only: [:index]
    resources :symbol_configs, only: [:index, :create, :update, :destroy]
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
