# frozen_string_literal: true

module Admin
  # The category tree the storefront browses by.
  #
  # Imported listings arrive with the source's own path, so this is where the
  # taxonomy is tidied: rename a branch, move it, archive it, or sweep away the
  # seeded branches that no listing ever landed in.
  class CategoriesController < BaseController
    before_action :require_view_categories!
    before_action :require_manage_categories!, only: [ :create, :update, :prune_empty ]
    before_action :set_category, only: [ :update ]

    def index
      @stats = stats
      @categories = filtered_categories
      ids = @categories.map(&:id)
      @product_counts = product_counts(ids)
      @children_counts = children_counts(ids)
      @parents = CommerceCategory.order(:name).where.not(id: ids)
      @all_categories = CommerceCategory.order(:name)
      @in_use_ids = Commerce::CategoryPruner.in_use_ids
    end

    # Pruning is destructive, so branches have to be creatable again from here.
    def create
      category = CommerceCategory.new(category_params)
      category.slug = category.name.to_s.parameterize if category.slug.blank?
      category.slug = "#{category.slug}-#{SecureRandom.hex(3)}" if CommerceCategory.exists?(slug: category.slug)

      if category.save
        log_admin_action("create_category", category.category_id, category_params.to_h)
        redirect_to admin_categories_path, notice: "Category \"#{category.name}\" added."
      else
        redirect_to admin_categories_path, alert: "Could not create the category: #{category.errors.full_messages.to_sentence}"
      end
    end

    def update
      if @category.update(category_params)
        log_admin_action("update_category", @category.category_id, category_params.to_h)
        redirect_to admin_categories_path, notice: "Category updated."
      else
        redirect_to admin_categories_path, alert: "Could not save: #{@category.errors.full_messages.to_sentence}"
      end
    end

    # Sweeps categories with no listings and no children. Nothing live is ever
    # touched: a category with either is kept.
    def prune_empty
      summary = Commerce::CategoryPruner.call(dry_run: false)
      log_admin_action("prune_empty_categories", "commerce_categories", removed: summary.removed, kept: summary.kept)

      if summary.removed.zero?
        redirect_to admin_categories_path, notice: "No empty categories to remove — every branch has listings or children."
      else
        redirect_to admin_categories_path,
          notice: "Removed #{summary.removed} empty categor#{'y' if summary.removed == 1}#{'ies' unless summary.removed == 1}. #{summary.kept} kept."
      end
    end

    private

    def set_category
      @category = CommerceCategory.find(params[:id])
    end

    def filtered_categories
      scope = CommerceCategory.includes(:parent_category).order(:parent_id, :sort_order, :name)
      if params[:query].present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%"
        scope = scope.where("LOWER(name) LIKE :pattern OR LOWER(slug) LIKE :pattern OR LOWER(category_id) LIKE :pattern", pattern: pattern)
      end
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.top_level if params[:depth] == "top"

      # "In use" and "empty" are branch-level: a parent stays in use while a
      # child holds stock, which is exactly what the pruner removes.
      scope = case params[:filled]
      when "with_products" then scope.where(id: Commerce::CategoryPruner.in_use_ids)
      when "empty" then scope.merge(Commerce::CategoryPruner.empty_scope)
      else scope
      end

      scope.limit(500)
    end

    # Counting per category in one pass: a listing counts for its category and
    # for its subcategory column, which is how the storefront filters.
    def product_counts(ids)
      return {} if ids.empty?

      counts = Hash.new(0)
      CommerceProduct.where(category_id: ids).group(:category_id).count.each { |id, count| counts[id] += count }
      CommerceProduct.where(subcategory_id: ids).group(:subcategory_id).count.each { |id, count| counts[id] += count }
      counts
    end

    def children_counts(ids)
      return {} if ids.empty?

      CommerceCategory.where(parent_id: ids).group(:parent_id).count
    end

    def stats
      in_use = Commerce::CategoryPruner.in_use_ids

      {
        total: CommerceCategory.count,
        top_level: CommerceCategory.top_level.count,
        with_products: in_use.size,
        empty: CommerceCategory.where.not(id: in_use).count,
        inactive: CommerceCategory.where(status: "inactive").count,
        filed_listings: CommerceProduct.where.not(category_id: nil).count
      }
    end

    def category_params
      params.require(:commerce_category).permit(:name, :slug, :description, :icon, :sort_order, :status, :parent_id)
    end

    def require_view_categories!
      require_admin_permission!(:view_categories)
    end

    def require_manage_categories!
      require_admin_permission!(:manage_categories)
    end
  end
end
