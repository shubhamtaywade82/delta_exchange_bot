Rails.application.routes.draw do
  namespace :api do
    get "dashboard" => "dashboard#index"
    resources :positions, only: [:index]
    resources :trades, only: [:index]
    resources :settings, only: [:index, :update]
    resources :trading_sessions, only: [:index, :create, :destroy]
    get "strategy_status" => "strategy_status#index"
    get "wallet"          => "wallet#index"
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
