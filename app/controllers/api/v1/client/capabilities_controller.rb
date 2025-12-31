class Api::V1::Client::CapabilitiesController < ApplicationController
  before_action :authenticate_tep_token, only: [ :show ]

  CAPABILITIES = {
    camera: {
      supported: true,
      permission_required: true,
      methods: [ "photo", "video" ],
      constraints: {
        video: {
          width: { ideal: 1920 },
          height: { ideal: 1080 },
          frameRate: { ideal: 30 }
        }
      }
    },
    location: {
      supported: true,
      permission_required: true,
      accuracy: {
        default: "high",
        options: [ "high", "low" ]
      },
      timeout: 30000
    },
    payment: {
      supported: true,
      permission_required: false,
      currencies: [ "USD", "EUR", "GBP" ],
      max_amount: 50000.00,
      mfa_threshold: 50.00,
      methods: [ "transaction_pin", "biometric", "totp" ]
    },
    storage: {
      supported: true,
      permission_required: false,
      quota_bytes: 10_485_760,
      max_key_size: 1_048_576,
      max_keys: 1000,
      ttl_support: true,
      max_ttl_seconds: 2_592_000
    },
    biometric: {
      supported: true,
      permission_required: false,
      methods: [ "fingerprint", "face_recognition", "voice" ],
      attestation: true
    },
    network: {
      supported: true,
      permission_required: false,
      features: [ "websocket", "fetch", "eventsource" ],
      timeouts: {
        default: 30000,
        long_poll: 60000
      }
    },
    messaging: {
      supported: true,
      permission_required: true,
      features: [ "send_message", "send_media", "send_location", "typing_indicator" ],
      rate_limits: {
        messages_per_minute: 60,
        burst_size: 10
      }
    },
    wallet: {
      supported: true,
      permission_required: true,
      features: [ "balance", "transfer", "history", "verification" ],
      p2p: {
        supported: true,
        max_amount: 50000.00,
        expiry_hours: 24
      },
      gifts: {
        supported: true,
        min_participants: 2,
        max_participants: 100,
        max_amount: 50000.00
      }
    },
    webview: {
      supported: true,
      permission_required: false,
      features: [ "javascript", "localstorage", "postmessage" ],
      security: {
        csp_required: true,
        xss_protection: true
      }
    },
    keyboard: {
      supported: true,
      permission_required: false,
      types: [ "text", "number", "email", "phone", "custom" ],
      features: [ "shortcuts", "autocomplete" ]
    }
  }.freeze

  SERVER_VERSION = "1.5.0"
  SERVER_NAME = "TMCP Server"

  def show
    render json: {
      capabilities: CAPABILITIES,
      server: {
        name: SERVER_NAME,
        version: SERVER_VERSION,
        api_version: "v1"
      },
      rate_limits: rate_limit_info,
      timestamp: Time.current.iso8601
    }
  end

  def check_capability
    capability_name = params[:capability]
    requested_features = params[:features] || {}

    unless CAPABILITIES.key?(capability_name)
      return render json: {
        supported: false,
        error: "UNKNOWN_CAPABILITY",
        message: "Capability '#{capability_name}' is not defined"
      }, status: :bad_request
    end

    capability = CAPABILITIES[capability_name]

    unsupported_features = requested_features.keys - (capability[:features] || [])
    missing_features = capability[:features] - requested_features.keys if capability[:features]

    render json: {
      supported: capability[:supported],
      capability: capability_name,
      features: {
        requested: requested_features,
        supported: capability[:features] || [],
        unsupported: unsupported_features,
        missing: missing_features || []
      },
      permission_required: capability[:permission_required],
      message: unsupported_features.empty? ? "All requested features are supported" : "Some features are not supported"
    }
  end

  private

  def authenticate_tep_token
    auth_header = request.headers["Authorization"]
    return if auth_header&.start_with?("Bearer ")

    render json: {
      error: "missing_token",
      message: "TEP token required for capability negotiation"
    }, status: :unauthorized
  end

  def rate_limit_info
    {
      general: {
        requests_per_minute: 100,
        burst_size: 20
      },
      api: {
        requests_per_minute: 60,
        burst_size: 10
      },
      storage: {
        requests_per_minute: 100,
        bytes_per_minute: 1_048_576
      }
    }
  end
end
