# TMCP Server Rails Monorepo Implementation Plan

## 1. Overview

This document outlines the implementation plan for TMCP (Tween Mini-App Communication Protocol) Server as a Ruby on Rails monorepo, leveraging Rails' strengths in rapid development, convention over configuration, and mature ecosystem while maintaining the ability to refactor to microservices later if needed.

## 2. Rails Monorepo Structure

```
tmcp-server/
├── app/
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── v1/
│   │   │   │   ├── authentication_controller.rb
│   │   │   │   ├── payments_controller.rb
│   │   │   │   ├── storage_controller.rb
│   │   │   │   ├── app_store_controller.rb
│   │   │   │   └── app_lifecycle_controller.rb
│   │   └── concerns/
│   │       ├── authenticatable.rb
│   │       ├── rate_limitable.rb
│   │       └── mfa_required.rb
│   ├── models/
│   │   ├── user.rb
│   │   ├── oauth_client.rb
│   │   ├── mini_app.rb
│   │   ├── payment_transaction.rb
│   │   ├── storage_entry.rb
│   │   ├── app_review.rb
│   │   ├── mfa_method.rb
│   │   └── device_registration.rb
│   ├── services/
│   │   ├── authentication_service.rb
│   │   ├── payment_service.rb
│   │   ├── storage_service.rb
│   │   ├── app_store_service.rb
│   │   ├── mfa_service.rb
│   │   └── tween_pay_client.rb
│   ├── jobs/
│   │   ├── payment_processing_job.rb
│   │   ├── storage_sync_job.rb
│   │   ├── app_installation_job.rb
│   │   └── cleanup_job.rb
│   ├── serializers/
│   │   ├── user_serializer.rb
│   │   ├── payment_transaction_serializer.rb
│   │   ├── storage_entry_serializer.rb
│   │   └── mini_app_serializer.rb
│   └── policies/
│       ├── application_policy.rb
│       ├── user_policy.rb
│       ├── payment_transaction_policy.rb
│       └── storage_entry_policy.rb
├── config/
│   ├── routes.rb
│   ├── application.rb
│   ├── environments/
│   ├── initializers/
│   │   ├── redis.rb
│   │   ├── sidekiq.rb
│   │   └── tween_pay.rb
│   └── locales/
├── db/
│   ├── migrate/
│   ├── seeds.rb
│   └── schema.rb
├── lib/
│   ├── tmcp/
│   │   ├── state_machine.rb
│   │   ├── mfa_challenge.rb
│   │   ├── rate_limiter.rb
│   │   └── protocol_validator.rb
│   └── tasks/
├── spec/
│   ├── controllers/
│   ├── models/
│   ├── services/
│   ├── jobs/
│   └── factories/
├── public/
├── storage/
├── vendor/
├── Gemfile
├── Gemfile.lock
├── README.md
└── docker-compose.yml
```

## 3. Rails Application Architecture

### 3.1 API Structure

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # API versioning
  namespace :api do
    namespace :v1 do
      # Authentication endpoints
      namespace :auth do
        post '/authorize', to: 'authentication#authorize'
        post '/token', to: 'authentication#token'
        post '/revoke', to: 'authentication#revoke'
        post '/mfa/challenge', to: 'authentication#mfa_challenge'
        post '/mfa/verify', to: 'authentication#mfa_verify'
      end
      
      # Payment endpoints
      resources :payments, only: [:create, :show] do
        member do
          post '/authorize', to: 'payments#authorize'
          post '/cancel', to: 'payments#cancel'
          post '/refund', to: 'payments#refund'
        end
      end
      
      # Storage endpoints
      namespace :storage do
        get '/:user_id/:app_id/:key', to: 'storage#show'
        put '/:user_id/:app_id/:key', to: 'storage#update'
        delete '/:user_id/:app_id/:key', to: 'storage#destroy'
        post '/:user_id/:app_id/batch', to: 'storage#batch'
      end
      
      # App Store endpoints
      namespace :store do
        get '/apps', to: 'app_store#index'
        get '/apps/:id', to: 'app_store#show'
        post '/apps/:id/install', to: 'app_store#install'
        post '/apps/:id/uninstall', to: 'app_store#uninstall'
        get '/apps/:id/reviews', to: 'app_store#reviews'
        post '/apps/:id/reviews', to: 'app_store#create_review'
      end
      
      # App Lifecycle endpoints
      namespace :lifecycle do
        get '/events', to: 'app_lifecycle#events'
        post '/events', to: 'app_lifecycle#create_event'
      end
    end
  end
  
  # Health check
  get '/health', to: 'application#health'
  get '/ready', to: 'application#ready'
end
```

### 3.2 Authentication Controller

```ruby
# app/controllers/api/v1/authentication_controller.rb
class Api::V1::AuthenticationController < ApplicationController
  skip_before_action :authenticate_user, only: [:authorize, :token]
  before_action :validate_oauth_client
  
  def authorize
    client = OAuthClient.find_by(client_id: params[:client_id])
    
    unless client&.verify_redirect_uri(params[:redirect_uri])
      render json: { error: 'invalid_redirect_uri' }, status: 400
      return
    end
    
    authorization = Authorization.create!(
      client: client,
      user: current_user,
      scopes: parse_scopes(params[:scope]),
      code_challenge: params[:code_challenge],
      code_challenge_method: params[:code_challenge_method]
    )
    
    render json: {
      authorization_code: authorization.code,
      redirect_uri: build_redirect_uri(authorization)
    }
  end
  
  def token
    authorization = Authorization.find_by(code: params[:code])
    
    unless authorization&.verify_code_verifier(params[:code_verifier])
      render json: { error: 'invalid_grant' }, status: 400
      return
    end
    
    token = JWTService.encode({
      sub: authorization.user.id,
      client_id: authorization.client.client_id,
      scopes: authorization.scopes,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      jti: SecureRandom.uuid
    })
    
    refresh_token = JWTService.encode({
      sub: authorization.user.id,
      client_id: authorization.client.client_id,
      type: 'refresh',
      exp: 30.days.from_now.to_i
    })
    
    render json: {
      access_token: token,
      refresh_token: refresh_token,
      token_type: 'Bearer',
      expires_in: 3600
    }
  end
  
  def mfa_challenge
    payment = PaymentTransaction.find(params[:payment_id])
    
    unless payment&.user == current_user
      render json: { error: 'unauthorized' }, status: 401
      return
    end
    
    unless payment.requires_mfa?
      render json: { error: 'mfa_not_required' }, status: 400
      return
    end
    
    challenge = MFAService.initiate_challenge(
      user: current_user,
      payment: payment,
      method: params[:method] || 'transaction_pin'
    )
    
    render json: {
      challenge_id: challenge.id,
      method: challenge.method_type,
      expires_at: challenge.expires_at
    }
  end
  
  def mfa_verify
    challenge = MFAChallenge.find(params[:challenge_id])
    
    unless challenge&.user == current_user
      render json: { error: 'unauthorized' }, status: 401
      return
    end
    
    if MFAService.verify_challenge(challenge, params[:response])
      render json: { status: 'verified' }
    else
      render json: { error: 'invalid_mfa_credentials' }, status: 401
    end
  end
  
  private
  
  def validate_oauth_client
    client_id = request.headers['X-Client-ID']
    client_secret = request.headers['X-Client-Secret']
    
    @client = OAuthClient.find_by(client_id: client_id)
    
    unless @client&.verify_secret(client_secret)
      render json: { error: 'invalid_client' }, status: 401
    end
  end
  
  def parse_scopes(scope_string)
    scope_string&.split(' ') || ['profile']
  end
end
```

### 3.3 Payment Controller

```ruby
# app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ApplicationController
  before_action :authenticate_user
  before_action :find_payment, only: [:show, :authorize, :cancel, :refund]
  
  def create
    payment = PaymentTransaction.new(payment_params)
    payment.user = current_user
    payment.state = 'initiated'
    
    if payment.save
      PaymentProcessingJob.perform_later(payment.id)
      render json: PaymentTransactionSerializer.new(payment).as_json, status: 201
    else
      render json: { errors: payment.errors.full_messages }, status: 400
    end
  end
  
  def show
    render json: PaymentTransactionSerializer.new(@payment).as_json
  end
  
  def authorize
    unless @payment.user == current_user
      render json: { error: 'unauthorized' }, status: 401
      return
    end
    
    if @payment.requires_mfa?
      unless @payment.mfa_verified?
        render json: { 
          error: 'MFA_REQUIRED',
          details: {
            payment_id: @payment.id,
            mfa_methods: current_user.available_mfa_methods
          }
        }, status: 428
        return
      end
    end
    
    @payment.authorize!
    PaymentProcessingJob.perform_later(@payment.id, 'process')
    
    render json: { status: 'authorized' }
  end
  
  def cancel
    unless @payment.user == current_user
      render json: { error: 'unauthorized' }, status: 401
      return
    end
    
    @payment.cancel!
    render json: { status: 'cancelled' }
  end
  
  def refund
    unless @payment.user == current_user
      render json: { error: 'unauthorized' }, status: 401
      return
    end
    
    unless @payment.completed?
      render json: { error: 'payment_not_completed' }, status: 400
      return
    end
    
    RefundProcessingJob.perform_later(@payment.id, refund_params[:amount])
    
    render json: { status: 'refund_initiated' }
  end
  
  private
  
  def find_payment
    @payment = PaymentTransaction.find(params[:id])
  end
  
  def payment_params
    params.require(:payment).permit(:amount, :currency, :description, :app_id, :metadata)
  end
  
  def refund_params
    params.permit(:amount)
  end
end
```

### 3.4 Storage Controller

```ruby
# app/controllers/api/v1/storage_controller.rb
class Api::V1::StorageController < ApplicationController
  before_action :authenticate_user
  before_action :validate_storage_access
  
  def show
    entry = StorageService.get(
      user: current_user,
      app: @app,
      key: params[:key]
    )
    
    if entry
      render json: {
        key: entry.key,
        value: entry.value,
        content_type: entry.content_type,
        size: entry.size,
        updated_at: entry.updated_at
      }
    else
      render json: { error: 'key_not_found' }, status: 404
    end
  end
  
  def update
    result = StorageService.set(
      user: current_user,
      app: @app,
      key: params[:key],
      value: request.raw_post,
      content_type: request.content_type,
      options: storage_options
    )
    
    if result[:success]
      render json: { 
        key: params[:key],
        size: result[:size],
        quota_used: result[:quota_used],
        quota_remaining: result[:quota_remaining]
      }
    else
      render json: { error: result[:error] }, status: 400
    end
  end
  
  def destroy
    result = StorageService.delete(
      user: current_user,
      app: @app,
      key: params[:key]
    )
    
    if result[:success]
      render json: { status: 'deleted' }
    else
      render json: { error: result[:error] }, status: 400
    end
  end
  
  def batch
    operations = params[:operations] || []
    results = StorageService.batch_operations(
      user: current_user,
      app: @app,
      operations: operations
    )
    
    render json: { results: results }
  end
  
  private
  
  def validate_storage_access
    @app = MiniApp.find(params[:app_id])
    
    unless @app
      render json: { error: 'app_not_found' }, status: 404
      return
    end
    
    # Check if user has access to this app
    installation = AppInstallation.find_by(user: current_user, app: @app)
    
    unless installation
      render json: { error: 'access_denied' }, status: 403
    end
  end
  
  def storage_options
    {
      ttl: params[:ttl],
      content_type: request.content_type
    }.compact
  end
end
```

## 4. Service Layer Architecture

### 4.1 Payment Service

```ruby
# app/services/payment_service.rb
class PaymentService
  include TMCP::StateMachine
  
  def initialize(payment)
    @payment = payment
  end
  
  def process
    @payment.validate!
    
    if @payment.requires_mfa?
      @payment.require_mfa!
      return { status: 'mfa_required', mfa_methods: available_mfa_methods }
    end
    
    @payment.authorize!
    process_with_tweenpay
  end
  
  def process_with_tweenpay
    @payment.process!
    
    response = TweenPayClient.create_payment({
      user_id: @payment.user.id,
      amount: @payment.amount,
      currency: @payment.currency,
      description: @payment.description,
      metadata: @payment.metadata
    })
    
    if response.success?
      @payment.complete!
      @payment.update(tweenpay_transaction_id: response.transaction_id)
      
      # Send notifications
      PaymentNotificationJob.perform_later(@payment.id, 'completed')
      
      { status: 'completed', transaction_id: response.transaction_id }
    else
      @payment.fail!
      @payment.update(failure_reason: response.error_message)
      
      PaymentNotificationJob.perform_later(@payment.id, 'failed')
      
      { status: 'failed', error: response.error_message }
    end
  rescue StandardError => e
    @payment.fail!
    @payment.update(failure_reason: e.message)
    
    Rails.logger.error "Payment processing error: #{e.message}"
    { status: 'failed', error: 'internal_error' }
  end
  
  private
  
  def available_mfa_methods
    @payment.user.mfa_methods.active.pluck(:method_type)
  end
end
```

### 4.2 Storage Service

```ruby
# app/services/storage_service.rb
class StorageService
  def self.get(user:, app:, key:)
    # Try cache first
    cache_key = "storage:#{user.id}:#{app.id}:#{key}"
    cached = Rails.cache.read(cache_key)
    return cached if cached
    
    # Fallback to database
    entry = StorageEntry.find_by(
      user: user,
      app: app,
      key: key
    )
    
    # Update cache
    Rails.cache.write(cache_key, entry, expires_in: entry&.ttl)
    
    entry
  end
  
  def self.set(user:, app:, key:, value:, content_type: 'application/octet-stream', options: {})
    # Check quota
    quota = StorageQuota.find_or_create_by(user: user, app: app)
    
    if quota.exceeded?(value.bytesize)
      return { 
        success: false, 
        error: 'STORAGE_QUOTA_EXCEEDED',
        quota_used: quota.used_bytes,
        quota_remaining: quota.remaining_bytes
      }
    end
    
    # Create or update entry
    entry = StorageEntry.find_or_initialize_by(
      user: user,
      app: app,
      key: key
    )
    
    entry.value = value
    entry.content_type = content_type
    entry.size = value.bytesize
    entry.ttl = options[:ttl]
    entry.save!
    
    # Update quota
    quota.update_usage(entry.size)
    
    # Update cache
    cache_key = "storage:#{user.id}:#{app.id}:#{key}"
    Rails.cache.write(cache_key, entry, expires_in: entry.ttl)
    
    {
      success: true,
      size: entry.size,
      quota_used: quota.used_bytes,
      quota_remaining: quota.remaining_bytes
    }
  end
  
  def self.delete(user:, app:, key:)
    entry = StorageEntry.find_by(
      user: user,
      app: app,
      key: key
    )
    
    unless entry
      return { success: false, error: 'key_not_found' }
    end
    
    # Update quota
    quota = StorageQuota.find_by(user: user, app: app)
    quota.update_usage(-entry.size)
    
    # Delete entry
    entry.destroy
    
    # Clear cache
    cache_key = "storage:#{user.id}:#{app.id}:#{key}"
    Rails.cache.delete(cache_key)
    
    { success: true }
  end
  
  def self.batch_operations(user:, app:, operations:)
    results = []
    
    StorageEntry.transaction do
      operations.each do |op|
        case op['type']
        when 'get'
          result = get(user: user, app: app, key: op['key'])
          results.push({ operation: op, result: result })
        when 'set'
          result = set(
            user: user, 
            app: app, 
            key: op['key'], 
            value: op['value'],
            content_type: op['content_type'],
            options: op['options'] || {}
          )
          results.push({ operation: op, result: result })
        when 'delete'
          result = delete(user: user, app: app, key: op['key'])
          results.push({ operation: op, result: result })
        end
      end
    end
    
    results
  end
end
```

## 5. State Machine Implementation

```ruby
# lib/tmcp/state_machine.rb
module TMCP
  class StateMachine
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def state_machine(attribute, options = {})
        states = options[:states] || {}
        initial_state = options[:initial]
        
        define_method("#{attribute}=") do |new_state|
          old_state = send(attribute)
          
          if valid_transition?(old_state, new_state, states)
            send("#{attribute}_will_change!", old_state, new_state)
            instance_variable_set("@#{attribute}", new_state)
            send("#{attribute}_did_change!", old_state, new_state)
          else
            raise InvalidTransitionError, "Invalid transition from #{old_state} to #{new_state}"
          end
        end
        
        define_method("#{attribute}") do
          instance_variable_get("@#{attribute}")
        end
        
        # Set initial state
        after_initialize { send("#{attribute}=", initial_state) if initial_state }
      end
      
      private
      
      def valid_transition?(from, to, states)
        return true if from.nil? # Initial state
        
        from_state = states[from.to_sym]
        return false unless from_state
        
        from_state[:transitions].include?(to.to_sym)
      end
    end
  end
  
  class InvalidTransitionError < StandardError; end
end
```

## 6. MFA Implementation

```ruby
# app/services/mfa_service.rb
class MFAService
  def self.initiate_challenge(user:, payment:, method:)
    mfa_method = user.mfa_methods.find_by(method_type: method)
    
    unless mfa_method
      raise ArgumentError, "MFA method #{method} not found for user"
    end
    
    case method
    when 'transaction_pin'
      initiate_pin_challenge(user, payment, mfa_method)
    when 'biometric'
      initiate_biometric_challenge(user, payment, mfa_method)
    when 'totp'
      initiate_totp_challenge(user, payment, mfa_method)
    else
      raise ArgumentError, "Unsupported MFA method: #{method}"
    end
  end
  
  def self.verify_challenge(challenge, response)
    case challenge.method_type
    when 'transaction_pin'
      verify_pin_challenge(challenge, response)
    when 'biometric'
      verify_biometric_challenge(challenge, response)
    when 'totp'
      verify_totp_challenge(challenge, response)
    end
  end
  
  private
  
  def self.initiate_pin_challenge(user, payment, mfa_method)
    # Generate random 6-digit code
    code = sprintf('%06d', rand(100000..999999))
    
    # Store encrypted code
    challenge = MFAChallenge.create!(
      user: user,
      payment: payment,
      method_type: 'transaction_pin',
      challenge_data: {
        encrypted_code: encrypt_code(code, user.encryption_key),
        attempts: 0
      },
      expires_at: 5.minutes.from_now
    )
    
    # Send code via preferred channel (SMS, email, etc.)
    NotificationService.send_mfa_code(user, code)
    
    challenge
  end
  
  def self.verify_pin_challenge(challenge, response)
    return false if challenge.expired?
    return false if challenge.attempts >= 3
    
    challenge_data = challenge.challenge_data
    decrypted_code = decrypt_code(challenge_data['encrypted_code'], challenge.user.encryption_key)
    
    if response == decrypted_code
      challenge.update!(status: 'verified', verified_at: Time.current)
      true
    else
      challenge.update!(
        attempts: challenge.attempts + 1,
        challenge_data: challenge_data.merge('attempts' => challenge.attempts + 1)
      )
      
      if challenge.attempts + 1 >= 3
        challenge.update!(status: 'failed')
      end
      
      false
    end
  end
end
```

## 7. TweenPay Integration

```ruby
# app/services/tween_pay_client.rb
class TweenPayClient
  BASE_URL = ENV['TWEENPAY_API_URL'] || 'https://api.tweenpay.com'
  API_KEY = ENV['TWEENPAY_API_KEY']
  
  def self.create_payment(payment_data)
    response = HTTParty.post(
      "#{BASE_URL}/payments",
      headers: {
        'Authorization' => "Bearer #{API_KEY}",
        'Content-Type' => 'application/json'
      },
      body: payment_data.to_json
    )
    
    handle_response(response)
  end
  
  def self.get_payment_status(payment_id)
    response = HTTParty.get(
      "#{BASE_URL}/payments/#{payment_id}",
      headers: {
        'Authorization' => "Bearer #{API_KEY}"
      }
    )
    
    handle_response(response)
  end
  
  def self.refund_payment(payment_id, amount = nil)
    response = HTTParty.post(
      "#{BASE_URL}/payments/#{payment_id}/refund",
      headers: {
        'Authorization' => "Bearer #{API_KEY}",
        'Content-Type' => 'application/json'
      },
      body: { amount: amount }.compact.to_json
    )
    
    handle_response(response)
  end
  
  private
  
  def self.handle_response(response)
    case response.code
    when 200..299
      {
        success: true,
        data: JSON.parse(response.body),
        transaction_id: JSON.parse(response.body)['id']
      }
    when 400..499
      {
        success: false,
        error: 'client_error',
        error_message: JSON.parse(response.body)['message']
      }
    when 500..599
      {
        success: false,
        error: 'server_error',
        error_message: 'Payment service temporarily unavailable'
      }
    else
      {
        success: false,
        error: 'unknown_error',
        error_message: 'Unknown error occurred'
      }
    end
  end
end
```

## 8. Background Jobs

```ruby
# app/jobs/payment_processing_job.rb
class PaymentProcessingJob < ApplicationJob
  queue_as :payments
  
  def perform(payment_id, action = 'process')
    payment = PaymentTransaction.find(payment_id)
    service = PaymentService.new(payment)
    
    case action
    when 'process'
      service.process
    when 'refund'
      service.refund
    end
  rescue StandardError => e
    Rails.logger.error "Payment job failed: #{e.message}"
    payment.fail!
    payment.update(failure_reason: e.message)
  end
end

# app/jobs/storage_sync_job.rb
class StorageSyncJob < ApplicationJob
  queue_as :storage
  
  def perform(user_id, app_id)
    user = User.find(user_id)
    app = MiniApp.find(app_id)
    
    # Process pending sync operations
    pending_operations = StorageSyncOperation.where(
      user: user,
      app: app,
      status: 'pending'
    )
    
    pending_operations.each do |op|
      result = case op.operation_type
      when 'set'
        StorageService.set(
          user: user,
          app: app,
          key: op.key,
          value: op.value,
          content_type: op.content_type
        )
      when 'delete'
        StorageService.delete(
          user: user,
          app: app,
          key: op.key
        )
      end
      
      op.update!(
        status: result[:success] ? 'completed' : 'failed',
        processed_at: Time.current,
        error_message: result[:error]
      )
    end
  end
end
```

## 9. Configuration and Initializers

```ruby
# config/initializers/redis.rb
redis_config = {
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/0',
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
  network_timeout: 5,
  reconnect_attempts: 3
}

if Rails.env.production?
  redis_config[:password] = ENV['REDIS_PASSWORD']
  redis_config[:ssl] = true
end

$redis = Redis.new(redis_config)
Rails.cache = ActiveSupport::Cache::RedisCache.new($redis)

# config/initializers/sidekiq.rb
Sidekiq.configure_client do |config|
  config.redis = { 
    url: ENV['REDIS_URL'] || 'redis://localhost:6379/1'
  }
end

Sidekiq.configure_server do |config|
  config.redis = { 
    url: ENV['REDIS_URL'] || 'redis://localhost:6379/1'
  }
end

# config/initializers/tween_pay.rb
TweenPayClient.configure do |config|
  config.api_url = ENV['TWEENPAY_API_URL']
  config.api_key = ENV['TWEENPAY_API_KEY']
  config.timeout = 30
  config.retries = 3
end
```

## 10. Testing Strategy

```ruby
# spec/services/payment_service_spec.rb
RSpec.describe PaymentService do
  describe '#process' do
    let(:user) { create(:user) }
    let(:payment) { create(:payment_transaction, user: user, amount: 10000) }
    
    context 'when payment requires MFA' do
      before do
        allow(payment).to receive(:requires_mfa?).and_return(true)
      end
      
      it 'transitions to mfa_required state' do
        service = PaymentService.new(payment)
        result = service.process
        
        expect(result[:status]).to eq('mfa_required')
        expect(payment.state).to eq('mfa_required')
      end
    end
    
    context 'when payment does not require MFA' do
      before do
        allow(payment).to receive(:requires_mfa?).and_return(false)
        allow(TweenPayClient).to receive(:create_payment).and_return({
          success: true,
          transaction_id: 'tp_txn_123'
        })
      end
      
      it 'processes payment with TweenPay' do
        service = PaymentService.new(payment)
        result = service.process
        
        expect(TweenPayClient).to have_received(:create_payment)
        expect(result[:status]).to eq('completed')
        expect(payment.state).to eq('completed')
      end
    end
  end
end
```

## 11. Deployment Configuration

```dockerfile
# Dockerfile for Rails
FROM ruby:3.1.2-alpine AS base

# Install dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    postgresql-dev \
    tzdata

WORKDIR /app

# Copy gem files
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle install --jobs 4 --retry 3 --deployment --without development test

# Copy application code
COPY . .

# Precompile assets
RUN SECRET_KEY_BASE=dummy rails assets:precompile

# Production stage
FROM ruby:3.1.2-alpine AS production
RUN apk add --no-cache \
    postgresql-client \
    tzdata \
    curl

# Copy from base stage
COPY --from=base /usr/local/bundle/ /usr/local/bundle/
COPY --from=base /app /app

# Create app user
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001

USER appuser
WORKDIR /app

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - RAILS_ENV=development
      - DATABASE_URL=postgresql://postgres:password@db:5432/tmcp_development
      - REDIS_URL=redis://redis:6379/0
      - TWEENPAY_API_URL=http://tweenpay_mock:4000
    depends_on:
      - db
      - redis
      - tweenpay_mock
    volumes:
      - .:/app
    command: bundle exec rails server -b 0.0.0.0

  db:
    image: postgres:14
    environment:
      - POSTGRES_DB=tmcp_development
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  tweenpay_mock:
    build: ./tweenpay_mock
    ports:
      - "4000:4000"
    environment:
      - MOCK_MODE=true

  sidekiq:
    build: .
    environment:
      - RAILS_ENV=development
      - DATABASE_URL=postgresql://postgres:password@db:5432/tmcp_development
      - REDIS_URL=redis://redis:6379/1
    depends_on:
      - db
      - redis
    volumes:
      - .:/app
    command: bundle exec sidekiq -C config/sidekiq.yml

volumes:
  postgres_data:
  redis_data:
```

This Rails monorepo implementation provides a solid foundation for TMCP server while maintaining the flexibility to refactor to microservices later if needed. It leverages Rails' strengths in rapid development, convention over configuration, and mature ecosystem while ensuring full compliance with the TMCP protocol.