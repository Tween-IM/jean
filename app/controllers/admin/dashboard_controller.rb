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

      @commerce = {
        orders_today: safe_value { CommerceOrder.where("created_at >= ?", Time.current.beginning_of_day).count },
        orders_7d: safe_value { CommerceOrder.where("created_at >= ?", 7.days.ago).count },
        open_orders: safe_value { CommerceOrder.where(status: OrdersController::OPEN_STATUSES).count },
        needs_fulfillment: safe_value {
          CommerceOrder.where(status: %w[paid processing], fulfillment_status: %w[unfulfilled partially_fulfilled]).count
        },
        system_open_orders: safe_value {
          CommerceOrder.where(commerce_merchant_id: CommerceMerchant.system_owned.select(:id), status: OrdersController::OPEN_STATUSES).count
        },
        gmv_30d_cents: safe_value {
          CommerceOrder.where(status: %w[paid processing fulfilled partially_fulfilled])
            .where("created_at >= ?", 30.days.ago).sum(:total_cents)
        },
        refunds_30d_cents: safe_value {
          CommerceOrder.where(status: %w[refunded partially_refunded]).where("updated_at >= ?", 30.days.ago).sum(:total_cents)
        },
        stores_without_logo: safe_value {
          CommerceStorefront.where.not(source_platform: nil).where(logo_url: [ nil, "" ]).count
        },
        listings_without_category: safe_value { CommerceProduct.where(category_id: nil).count },
        empty_categories: safe_value {
          in_use = (CommerceCategory.where.not(parent_id: nil).distinct.pluck(:parent_id) +
            CommerceProduct.where.not(category_id: nil).distinct.pluck(:category_id) +
            CommerceProduct.where.not(subcategory_id: nil).distinct.pluck(:subcategory_id)).compact.uniq
          CommerceCategory.where.not(id: in_use).count
        }
      }

      @attention_orders = safe_relation(CommerceOrder)
        .where(status: %w[pending_payment paid processing], fulfillment_status: %w[unfulfilled partially_fulfilled])
        .includes(:commerce_merchant)
        .order(:created_at)
        .limit(6)

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

    def safe_value(fallback = 0)
      yield
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "dashboard metric failed: #{e.message}"
      fallback
    end
  end
end
