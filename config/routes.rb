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
      get "storage/info", to: "storage#info"
      get "storage/:key", to: "storage#show"
      put "storage/:key", to: "storage#update"
      delete "storage/:key", to: "storage#destroy"
      post "storage/batch", to: "storage#batch"

       # Wallet endpoints
       get "wallet/balance", to: "wallet#balance"
       get "wallet/transactions", to: "wallet#transactions"
       get "wallet/verification", to: "wallet#verification"
       post "wallet/p2p/initiate", to: "wallet#initiate_p2p"
       post "wallet/p2p/:transfer_id/accept", to: "wallet#accept_p2p"
       post "wallet/p2p/:transfer_id/reject", to: "wallet#reject_p2p"
       get "wallet/resolve/:user_id", to: "wallet#resolve"
       post "wallet/resolve/batch", to: "wallet#resolve_batch"

        # External account endpoints (TMCP Protocol Section 6.5)
        post "wallet/external/link", to: "wallet#link_external_account"
        post "wallet/external/verify", to: "wallet#verify_external_account"

       # Payment endpoints (TMCP Section 7.3-7.4)
       post "payments/request", to: "payments#create"
       post "payments/:payment_id/authorize", to: "payments#authorize"
       post "payments/:payment_id/refund", to: "payments#refund"
       post "payments/:payment_id/mfa/challenge", to: "payments#mfa_challenge"
       post "payments/:payment_id/mfa/verify", to: "payments#mfa_verify"

          # OAuth endpoints (TMCP Protocol Section 4.2)
          get "oauth/authorize", to: "oauth#authorize"
          post "oauth/token", to: "oauth#token"
          post "oauth2/introspect", to: "oauth#introspect"
          post "oauth2/consent", to: "oauth#consent"
          get "oauth2/callback", to: "oauth#callback"

         # Device Authorization Grant (RFC 8628) - PROTO Section 4.3.2
         post "oauth2/device/authorization", to: "oauth/device_authorization#create"
         get "oauth2/device", to: "oauth/device_authorization#show"
         post "oauth2/device/token", to: "oauth/device_token#create"

       # Store endpoints (TMCP Protocol Section 16.6)
       get "store/categories", to: "store#categories"
       get "store/apps", to: "store#apps"
       post "store/apps/:miniapp_id/install", to: "store#install"
       delete "store/apps/:miniapp_id/install", to: "store#uninstall"

        # Client endpoints (TMCP Protocol Section 10.5, 16.8)
        get "capabilities", to: "client#capabilities"
        get "capabilities/:capability", to: "client#check_capability"
        post "client/bootstrap", to: "client#bootstrap"
        post "client/check-updates", to: "client#check_updates"

        # Permission Revocation endpoints (TMCP Protocol Section 5.6)
        post "auth/revoke", to: "auth_revocation#create"
        delete "auth/revoke", to: "auth_revocation#user_revoke"
        post "auth/revoke/webhook", to: "auth_revocation#webhook"

        # Mini-App Registration endpoints (TMCP Protocol Section 9.1)
        post "mini-apps/register", to: "mini_app_registration#create"
        get "mini-apps/:miniapp_id", to: "mini_app_registration#show"
        patch "mini-apps/:miniapp_id", to: "mini_app_registration#update"
        post "mini-apps/:miniapp_id/submit", to: "mini_app_registration#submit_for_review"
        post "mini-apps/:miniapp_id/appeal", to: "mini_app_registration#appeal"
        get "mini-apps/:miniapp_id/status", to: "mini_app_registration#check_status"
        get "mini-apps/:miniapp_id/automated-review", to: "mini_app_registration#automated_review"

         # Room Member Wallet Status (TMCP Protocol Section 6.3.9)
         get "wallet/room/:room_id/members", to: "wallet#room_member_wallets"
    end
  end
  use_doorkeeper

   # Matrix Application Service endpoints (PROTO Section 3.1.2)
   scope "/_matrix/app/v1" do
     post "transactions/:txn_id", to: "matrix#transactions"
     get "users/*user_id", to: "matrix#user", constraints: { user_id: /.*/ }
     get "rooms/*room_alias", to: "matrix#room", constraints: { room_alias: /.*/ }
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
