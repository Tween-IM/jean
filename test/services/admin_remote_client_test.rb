require "test_helper"

class AdminRemoteClientTest < ActiveSupport::TestCase
  test "synapse preserves opaque pagination cursors and escapes matrix identifiers" do
    ENV['SYNAPSE_ADMIN_URL'] = 'https://matrix.test'
    ENV['SYNAPSE_ADMIN_TOKEN'] = 'test-token'
    stub_request(:get, 'https://matrix.test/_synapse/admin/v1/rooms?from=opaque-token&limit=25')
      .to_return(body: { rooms: [], total_rooms: 100, next_batch: 'opaque-next', prev_batch: 'opaque-prev' }.to_json)
    data = Admin::SynapseClient.new.list('rooms', page: 3, cursor: 'opaque-token')
    assert_equal 'opaque-next', data['next_cursor']
    assert_equal 'opaque-prev', data['previous_cursor']
    assert_equal 4, data['next_page']
    client = Admin::RemoteClient.new(url: 'https://matrix.test', token: 'test')
    assert_equal '%40alice%3Atween.im', client.segment('@alice:tween.im')
    assert_equal '%21a%2Fb%3Atween.im', client.segment('!a/b:tween.im')
  ensure
    ENV.delete('SYNAPSE_ADMIN_URL')
    ENV.delete('SYNAPSE_ADMIN_TOKEN')
  end

  test "malformed and forbidden responses do not leak upstream errors" do
    client = Admin::RemoteClient.new(url: 'https://service.test', token: 'test')
    stub_request(:get, 'https://service.test/data').to_return(body: 'private upstream stacktrace', status: 500)
    error = assert_raises(Admin::RemoteClient::Unavailable) { client.get('/data') }
    refute_includes error.message, 'stacktrace'
    stub_request(:get, 'https://service.test/data').to_return(body: '[]')
    assert_raises(Admin::RemoteClient::Unavailable) { client.get('/data') }
    stub_request(:get, 'https://service.test/data').to_return(status: 403)
    assert_raises(Admin::RemoteClient::Forbidden) { client.get('/data') }
  end

  test "MAS account details omit privileged fields" do
    ENV['MAS_ADMIN_URL'] = 'https://id.test'
    ENV['MAS_ADMIN_TOKEN'] = 'test-token'
    stub_request(:get, 'https://id.test/api/admin/v1/users/test-id').to_return(body: {
      data: { attributes: { username: 'alice', created_at: '2026-01-01', locked_at: nil, admin: true } }
    }.to_json)
    data = Admin::MasClient.new.person('test-id')
    assert_equal 'alice', data['username']
    refute data.key?('admin')
  ensure
    ENV.delete('MAS_ADMIN_URL')
    ENV.delete('MAS_ADMIN_TOKEN')
  end
  test "MAS obtains a fresh admin token from its dedicated confidential client" do
    ENV['MAS_ADMIN_URL'] = 'https://id.test'
    ENV['MAS_ADMIN_CLIENT_ID'] = 'workspace-client'
    ENV['MAS_ADMIN_CLIENT_SECRET'] = 'test-client-secret'
    stub_request(:post, 'https://id.test/oauth2/token')
      .with(basic_auth: ['workspace-client', 'test-client-secret'],
        body: { 'grant_type' => 'client_credentials', 'scope' => 'urn:mas:admin' })
      .to_return(body: { access_token: 'fresh-token' }.to_json)
    stub_request(:get, 'https://id.test/api/admin/v1/users/test-id')
      .with(headers: { 'Authorization' => 'Bearer fresh-token' })
      .to_return(body: { data: { attributes: { username: 'alice' } } }.to_json)
    assert_equal 'alice', Admin::MasClient.new.person('test-id')['username']
  ensure
    %w[MAS_ADMIN_URL MAS_ADMIN_CLIENT_ID MAS_ADMIN_CLIENT_SECRET].each { |key| ENV.delete(key) }
  end

end
