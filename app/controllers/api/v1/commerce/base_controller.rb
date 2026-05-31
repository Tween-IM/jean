# frozen_string_literal: true

module Api
  module V1
    module Commerce
      class BaseController < Api::BaseController
        include Api::TepAuthenticatable

        before_action :authenticate_tep_token

        private

        def find_merchant
          ::CommerceMerchant.find_by!(merchant_id: params[:merchant_id] || params[:id])
        end

        def find_product
          ::CommerceProduct.find_by!(product_id: params[:product_id] || params[:id])
        end

        def find_cart
          ::CommerceCart.find_by!(cart_id: params[:cart_id] || params[:id])
        end

        def find_checkout
          ::CommerceCheckout.find_by!(checkout_id: params[:checkout_id] || params[:id])
        end

        def find_order
          ::CommerceOrder.find_by!(order_id: params[:order_id] || params[:id])
        end

        def ensure_cart_owner(cart)
          return false if cart.buyer_user_id == @current_user.matrix_user_id

          render json: { error: "forbidden", message: "Cart belongs to another buyer" }, status: :forbidden
          true
        end

        def ensure_merchant_owner(merchant)
          return false if merchant.owner_user_id == @current_user.matrix_user_id

          render json: { error: "forbidden", message: "Merchant belongs to another owner" }, status: :forbidden
          true
        end

        def render_errors(record)
          render json: { error: "validation_failed", messages: record.errors.full_messages }, status: :unprocessable_entity
        end

        def merchant_json(merchant)
          {
            merchant_id: merchant.merchant_id,
            owner_user_id: merchant.owner_user_id,
            miniapp_id: merchant.miniapp_id,
            display_name: merchant.display_name,
            status: merchant.status,
            wallet_id: merchant.wallet_id,
            webhook_url: merchant.webhook_url,
            created_at: merchant.created_at
          }
        end

        def product_json(product)
          {
            product_id: product.product_id,
            merchant_id: product.commerce_merchant.merchant_id,
            merchant: merchant_json(product.commerce_merchant),
            storefront_id: product.commerce_storefront&.storefront_id,
            title: product.title,
            description: product.description,
            status: product.status,
            media_urls: product.media_urls,
            skus: product.commerce_skus.map { |sku| sku_json(sku) },
            created_at: product.created_at
          }
        end

        def storefront_json(storefront)
          {
            storefront_id: storefront.storefront_id,
            merchant_id: storefront.commerce_merchant.merchant_id,
            slug: storefront.slug,
            display_name: storefront.display_name,
            description: storefront.description,
            status: storefront.status,
            products_count: storefront.products.count,
            created_at: storefront.created_at
          }
        end

        def sku_json(sku)
          {
            sku_id: sku.sku_id,
            title: sku.title,
            price_cents: sku.price_cents,
            currency: sku.currency,
            inventory_status: sku.inventory_status,
            quantity_available: sku.quantity_available,
            properties: sku.properties
          }
        end

        def cart_json(cart)
          {
            cart_id: cart.cart_id,
            merchant_id: cart.commerce_merchant.merchant_id,
            buyer_user_id: cart.buyer_user_id,
            status: cart.status,
            subtotal_cents: cart.subtotal_cents,
            currency: cart.currency,
            items: cart.commerce_cart_items.includes(:commerce_sku).map { |item| cart_item_json(item) },
            updated_at: cart.updated_at
          }
        end

        def cart_item_json(item)
          {
            sku_id: item.commerce_sku.sku_id,
            product_id: item.commerce_sku.commerce_product.product_id,
            title: item.commerce_sku.title,
            quantity: item.quantity,
            unit_price_cents: item.unit_price_cents,
            currency: item.currency
          }
        end

        def checkout_json(checkout)
          {
            checkout_id: checkout.checkout_id,
            cart_id: checkout.commerce_cart.cart_id,
            status: checkout.status,
            payment_id: checkout.payment_id,
            order_id: checkout.order_id,
            expires_at: checkout.expires_at,
            metadata: checkout.metadata,
            created_at: checkout.created_at
          }
        end

        def order_json(order)
          {
            order_id: order.order_id,
            merchant_id: order.commerce_merchant.merchant_id,
            buyer_user_id: order.buyer_user_id,
            status: order.status,
            payment_id: order.payment_id,
            subtotal_cents: order.subtotal_cents,
            total_cents: order.total_cents,
            currency: order.currency,
            fulfillment_status: order.fulfillment_status,
            metadata: order.metadata,
            items: order.commerce_order_items.map { |item| order_item_json(item) },
            created_at: order.created_at
          }
        end

        def order_item_json(item)
          {
            sku_id: item.sku_id,
            title: item.title,
            quantity: item.quantity,
            unit_price_cents: item.unit_price_cents,
            total_cents: item.line_total_cents,
            currency: item.currency
          }
        end
      end
    end
  end
end
