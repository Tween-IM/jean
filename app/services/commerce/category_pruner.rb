# frozen_string_literal: true

module Commerce
  # Finds and removes categories that no listing needs.
  #
  # The taxonomy was seeded ahead of the catalogue, and the importer files
  # listings under the branches it discovers, so a seeded branch that no
  # listing ever landed in is dead weight on the browse screen.
  #
  # "Empty" means the whole branch: neither the category nor anything beneath
  # it holds a listing. So a parent whose only child is also empty is empty.
  # Deletion walks bottom-up — `CommerceCategory#subcategories` is
  # `dependent: :destroy`, and the sweep must never take a live child with it.
  class CategoryPruner
    Summary = Struct.new(:scanned, :removed, :kept, keyword_init: true) do
      def to_s
        "categories scanned: #{scanned} | removed: #{removed} | kept: #{kept}"
      end
    end

    class << self
      # Categories that hold listings directly, through either column: the
      # storefront filters on `category_id IN branch OR subcategory_id IN branch`.
      def filed_ids
        (
          CommerceProduct.where.not(category_id: nil).distinct.pluck(:category_id) +
          CommerceProduct.where.not(subcategory_id: nil).distinct.pluck(:subcategory_id)
        ).compact.uniq
      end

      # Every category a listing needs: the ones filed on, plus all their
      # ancestors (so a parent branch stays while a child holds stock).
      def in_use_ids
        parents = CommerceCategory.pluck(:id, :parent_id).to_h
        in_use = filed_ids.index_with(true)

        parents.each_key do |id|
          next unless in_use[id]

          parent_id = parents[id]
          while parent_id && !in_use[parent_id]
            in_use[parent_id] = true
            parent_id = parents[parent_id]
          end
        end

        in_use.keys
      end

      def empty_scope
        CommerceCategory.where.not(id: in_use_ids)
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @summary = Summary.new(scanned: 0, removed: 0, kept: 0)
    end

    def self.call(dry_run: true)
      new(dry_run: dry_run).call
    end

    def call
      empties = self.class.empty_scope.to_a
      @summary.removed = empties.size

      unless @dry_run
        # Deepest first, so a cascade never orphans anything.
        empties.sort_by { |category| -category.full_hierarchy.size }.each(&:destroy)
      end

      @summary.kept = CommerceCategory.count
      @summary.scanned = @summary.removed + @summary.kept
      @summary
    end
  end
end
