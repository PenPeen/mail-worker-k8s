require 'sidekiq/web'

Rails.application.routes.draw do
  # Sidekiq Web UI
  mount Sidekiq::Web => '/sidekiq'
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  get '/health', to: 'application#health'

  # Email management routes
  root 'emails#index'
  resources :emails, only: [:index, :create, :destroy] do
    collection do
      post :bulk_send
      post :import_csv
    end
  end
end
