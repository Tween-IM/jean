require 'test_helper'

class Admin::MiniAppManagementTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(matrix_user_id: "@apps_#{SecureRandom.hex(4)}:tween.im", matrix_username: 'app_operator:tween.im', matrix_homeserver: 'tween.im', platform_role: 'super_admin')
    post admin_login_path, params: { admin_token: ENV['ADMIN_ACCESS_TOKEN'], matrix_user_id: @staff.matrix_user_id }
    @values = { app_id: "ma_test#{SecureRandom.hex(4)}", name: 'Operations test app', version: '1.0.0', classification: 'community', client_type: 'public', status: 'active' }
    @manifest = { entry_url: 'https://app.example.test', redirect_uris: "https://app.example.test/callback", permissions: ['user:read'] }
  end

  test 'hosted app creation retains a complete manifest and cannot directly publish' do
    assert_difference 'MiniApp.count' do
      post admin_mini_apps_path, params: { mini_app: @values, manifest: @manifest }
    end
    app = MiniApp.find_by!(app_id: @values[:app_id])
    assert_equal 'pending_review', app.status
    assert_equal 'public', app.client_type
    assert_equal ['user:read'], app.manifest['scopes']
    assert_equal ['https://app.example.test/callback'], app.manifest['redirect_uris']
    get admin_mini_app_path(app)
    assert_response :success
    assert_select 'h2', 'Launch & permissions'
    patch admin_mini_app_path(app), params: { mini_app: @values.merge(version: '1.0.1'), manifest: @manifest }
    assert_redirected_to admin_mini_app_path(app)
    assert_equal '1.0.1', app.reload.version
  end

  test 'stores reviewed artwork and includes it in the public catalog after activation' do
    icon = 'https://cdn.example.com/logo.png'
    cover = 'https://cdn.example.com/cover.png'
    shot = 'https://cdn.example.com/screen.webp'
    post admin_mini_apps_path, params: {
      mini_app: @values.merge(developer_name: 'Publisher name'),
      manifest: @manifest.merge(icon_url: icon, header_image: cover, screenshots: "#{shot}\n#{shot}")
    }
    app = MiniApp.find_by!(app_id: @values[:app_id])
    assert_equal 'pending_review', app.status
    assert_equal @manifest[:entry_url], app.manifest['entry_url']
    assert_equal cover, app.manifest['header_image']
    assert_equal [shot], app.manifest['screenshots']

    app.update!(status: :active)
    get '/api/v1/store/apps', params: { limit: 100 }
    listing = response.parsed_body.fetch('apps').find { |item| item['mini_app_id'] == app.app_id }
    assert_equal icon, listing['icon_url']
    assert_equal cover, listing['header_image']
    assert_equal [shot], listing['screenshots']
    assert_equal 'Publisher name', listing['developer_name']
  end

  test 'catalog selects website runtime only for standalone HTTPS listings or explicit overrides' do
    configs = {
      "public" => { "scopes" => ["public"] },
      "granted" => { "scopes" => ["user:read"] },
      "override" => { "scopes" => ["user:read"], "runtime" => "website" },
      "protected" => { "scopes" => ["public"], "runtime" => "tmcp" }
    }
    apps = configs.transform_values.with_index do |config, index|
      MiniApp.create!(
        app_id: "ma_runtime#{SecureRandom.hex(3)}", name: "Runtime test #{index}",
        status: :active, classification: :community, version: "1.0.0",
        manifest: { "entry_url" => "https://app.example.com" }.merge(config)
      )
    end
    get '/api/v1/store/apps', params: { limit: 100 }
    runtime_by_id = response.parsed_body.fetch('apps').to_h { |item| [item['mini_app_id'], item['runtime']] }
    assert_equal "website", runtime_by_id[apps.fetch("public").app_id]
    assert_equal "tmcp", runtime_by_id[apps.fetch("granted").app_id]
    assert_equal "website", runtime_by_id[apps.fetch("override").app_id]
    assert_equal "tmcp", runtime_by_id[apps.fetch("protected").app_id]
  end

  test 'website preview requires staff authentication and rejects invalid URLs' do
    post website_preview_admin_mini_apps_path, params: { url: 'tween-internal://wallet' }, as: :json
    assert_response :unprocessable_entity
    assert_match(/public HTTPS/, response.parsed_body.fetch('error'))

    open_session do |visitor|
      visitor.post website_preview_admin_mini_apps_path, params: { url: 'https://example.com' }, as: :json
      visitor.assert_redirected_to admin_login_path
    end
  end

  test 'invalid launch URLs and privileged community scopes fail visibly' do
    assert_no_difference 'MiniApp.count' do
      post admin_mini_apps_path, params: { mini_app: @values, manifest: @manifest.merge(entry_url: 'javascript:alert(1)') }
    end
    assert_response :unprocessable_entity
    assert_select '[role=alert]', text: /HTTPS/
    post admin_mini_apps_path, params: { mini_app: @values, manifest: @manifest.merge(permissions: ['wallet:admin']) }
    assert_response :unprocessable_entity
  end

  test 'packages retain a real digest and verifiable signature and stay private until activation' do
    previous_key = ENV['TMCP_PRIVATE_KEY']
    key = OpenSSL::PKey::RSA.new(2048)
    ENV['TMCP_PRIVATE_KEY'] = key.to_pem
    file = Tempfile.new(['miniapp', '.bundle'])
    bytes = 'Synthetic distribution artifact, never executable in this test.'
    file.write(bytes); file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, 'application/octet-stream', true, original_filename: 'test.bundle')
    post admin_mini_apps_path, params: { mini_app: @values.merge(bundle: upload), manifest: @manifest }
    app = MiniApp.find_by!(app_id: @values[:app_id])
    assert app.bundle.attached?
    artifact = app.manifest.fetch('bundle')
    assert_equal "sha256:#{Digest::SHA256.hexdigest(bytes)}", artifact['hash']
    assert key.public_key.verify(OpenSSL::Digest::SHA256.new, Base64.strict_decode64(artifact['signature']), app.bundle.download)
    get mini_app_package_path(app_id: app.app_id, version: app.version)
    assert_response :not_found
    post activate_admin_mini_app_path(app), params: { reason: 'Attempt activation before approval' }
    assert_response :unprocessable_entity
    post admin_approve_mini_app_review_path(app), params: { reason: 'Inspected launch configuration and package' }
    assert_equal 'approved', app.reload.status
    assert_equal false, Doorkeeper::Application.find_by!(uid: app.app_id).confidential?
    post activate_admin_mini_app_path(app), params: { reason: 'Publish the reviewed release' }
    assert_equal 'active', app.reload.status
    get mini_app_package_path(app_id: app.app_id, version: app.version)
    assert_response :redirect
    app.update!(classification: 'official')
    token = TepTokenService.encode({ user_id: @staff.matrix_user_id, miniapp_id: 'ma_client' }, scopes: ['user:read'])
    post '/api/v1/client/bootstrap', headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    assert_response :success
    published = response.parsed_body.fetch('official_apps').find { |row| row['miniapp_id'] == app.app_id }
    assert_equal artifact['hash'], published['bundle_hash']
    assert_not published['credentials'].key?('privileged_token')
    post '/api/v1/client/check-updates', params: { installed_apps: [{ miniapp_id: app.app_id, current_version: '0.9.0' }] }, headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    assert_response :success
    download = response.parsed_body.fetch('updates_available').find { |row| row['miniapp_id'] == app.app_id }.fetch('download')
    assert_equal artifact['hash'], download['hash']
    assert_equal artifact['signature'], download['signature']

    # A replacement is a new version and keeps the inspected prior artifact.
    replacement = Rack::Test::UploadedFile.new(file.path, 'application/octet-stream', true, original_filename: 'test.bundle')
    patch admin_mini_app_path(app), params: { mini_app: @values.merge(version: '1.0.1', classification: 'official', bundle: replacement), manifest: @manifest }
    assert_redirected_to admin_mini_app_path(app)
    assert_equal 'pending_review', app.reload.status
    assert_equal '1.0.1', app.manifest.dig('bundle', 'version')
    assert_equal 1, app.previous_bundles.count

  ensure
    ENV['TMCP_PRIVATE_KEY'] = previous_key
    file&.close!
  end

  test 'support can inspect but cannot create or approve app releases' do
    @staff.update!(platform_role: 'support')
    assert_no_difference 'MiniApp.count' do
      post admin_mini_apps_path, params: { mini_app: @values, manifest: @manifest }
    end
    assert_redirected_to admin_dashboard_path
  end
end
