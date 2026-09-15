# frozen_string_literal: true

module Commerce
  # Puts an imported listing into Tween's own category taxonomy.
  #
  # A marketplace hands us a chain of names ("Computers and Accessories" >
  # "Computing Accessories" > "Laptop Chargers"). Those branches mostly do
  # not exist here yet, and an imported listing with no category is invisible
  # to every category browse on the storefront — which filters on
  # `category_id`. So the chain is walked from the root, reusing what already
  # exists by name and creating only what is missing.
  #
  # Slugs are namespaced with their parent ("passenger-cars-suv") because
  # "Accessories" and "Cases" legitimately appear under several parents.
  class CategoryResolver
    #: A path deeper than this is marketplace noise, not a taxonomy.
    MAX_DEPTH = 6

    def initialize(path, platform: nil)
      @path = Array(path).map { |name| name.to_s.strip }.reject(&:empty?).uniq.first(MAX_DEPTH)
      @platform = platform
    end

    # Returns the hierarchy, outermost first, or [] when there is nothing
    # usable in the path.
    def resolve
      return [] if @path.empty?

      parent = nil
      @path.map { |name| parent = find_or_create(name, parent) }
    end

    private

    def find_or_create(name, parent)
      slug = [ parent&.slug, name.parameterize ].compact.join("-").presence
      existing = find_existing(name, slug)
      return existing if existing

      ::CommerceCategory.create!(
        name: name.titleize,
        slug: slug,
        parent_id: parent&.id,
        status: "active"
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent import created the same branch first; take theirs.
      find_existing(name, slug) || raise
    end

    def find_existing(name, slug)
      by_slug = ::CommerceCategory.find_by(slug: slug) if slug.present?
      return by_slug if by_slug

      ::CommerceCategory.where("lower(name) = ?", name.downcase).order(:id).first
    end
  end
end
