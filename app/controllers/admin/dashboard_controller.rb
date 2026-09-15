module Admin
  class DashboardController < BaseController
    def index
      @stats = {
        total_users: safe_count(User),
        active_users: safe_count_for(User, :active),
        suspended_users: safe_count_for(User, :suspended),
        total_mini_apps: safe_count(MiniApp),
        active_mini_apps: safe_count_for(MiniApp, :active),
        total_installations: safe_count(MiniappInstallation),
        total_storage_entries: safe_count(StorageEntry),
        total_gifts: safe_count(GroupGift),
        total_oauth_apps: safe_count(Doorkeeper::Application),
        total_oauth_tokens: safe_count(Doorkeeper::AccessToken),
        total_imported_products: safe_count(CommerceProduct.imported),
        total_imported_stores: safe_count(CommerceStorefront.imported),
        imported_stores_without_contact: safe_count(CommerceStorefront.imported.without_contact),
        last_import_sync_at: safe_maximum(CommerceProduct.imported, :source_synced_at)
      }

      @recent_users = safe_relation(User)
      @recent_mini_apps = safe_relation(MiniApp)
      @pending_approvals = safe_relation(AuthorizationApproval)
    end

    private

    def safe_count(model)
      model.count
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "safe_count failed for #{model}: #{e.message}"
      0
    end

    def safe_count_for(model, scope)
      model.send(scope).count
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "safe_count_for #{model}.#{scope} failed: #{e.message}"
      0
    end

    def safe_maximum(relation, column)
      relation.maximum(column)
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "safe_maximum for #{relation}.#{column} failed: #{e.message}"
      nil
    end

    def safe_relation(model)
      model.none
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "safe_relation for #{model} failed: #{e.message}"
      model.none
    end
  end
end
