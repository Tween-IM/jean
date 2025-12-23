Rails.application.routes.draw do
  get "health/check"
  namespace :api do
    namespace :v1 do
      # Gift endpoints (TMCP Section 7.5)
      post "gifts/create"
      post "gifts/:gift_id/open", to: "gifts#open"

      # Storage endpoints (TMCP Section 10.3)
      get "storage", to: "storage#index"
      post "storage", to: "storage#create"
      get "storage/:key", to: "storage#show"
      put "storage/:key", to: "storage#update"
      delete "storage/:key", to: "storage#destroy"
      post "storage/batch", to: "storage#batch"
      get "storage/info", to: "storage#info"

      # Wallet endpoints
      get "wallet/balance"
      get "wallet/transactions"
      post "wallet/p2p/initiate"
      post "wallet/p2p/:transfer_id/accept", to: "wallet#accept_p2p"
      post "wallet/p2p/:transfer_id/reject", to: "wallet#reject_p2p"
      get "wallet/resolve/:user_id", to: "wallet#resolve"

      # Payment endpoints (TMCP Section 7.3-7.4)
      post "payments/request"
      post "payments/:payment_id/authorize", to: "payments#authorize"
      post "payments/:payment_id/refund", to: "payments#refund"
      post "payments/:payment_id/mfa/challenge", to: "payments#mfa_challenge"
      post "payments/:payment_id/mfa/verify", to: "payments#mfa_verify"

      # OAuth endpoints (TMCP Protocol Section 4.2)
      get "oauth/authorize", to: "oauth#authorize"
      post "oauth/consent", to: "oauth#consent"
      post "oauth/token", to: "oauth#token"
      get "oauth2/callback", to: "oauth#callback"
    end
  end
  use_doorkeeper

  # Matrix Application Service endpoints (PROTO Section 3.1.2)
  scope "/_matrix/app/v1" do
    post "transactions/:txn_id", to: "matrix#transactions"
    get "users/:user_id", to: "matrix#user"
    get "rooms/:room_alias", to: "matrix#room"
    get "ping", to: "matrix#ping"
    get "thirdparty/location", to: "matrix#thirdparty_location"
    get "thirdparty/user", to: "matrix#thirdparty_user"
    get "thirdparty/location/:protocol", to: "matrix#thirdparty_location_protocol"
    get "thirdparty/user/:protocol", to: "matrix#thirdparty_user_protocol"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
