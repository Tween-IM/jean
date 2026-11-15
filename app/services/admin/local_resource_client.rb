module Admin
  class LocalResourceClient
    def initialize(resource)
      @resource = resource
      @model = resource.fetch(:model).constantize
    end

    def list(_key, query = {})
      scope = @model.order(created_at: :desc)
      if query[:status].present? && @model.column_names.include?("status")
        scope = scope.where(status: query[:status])
      end
      columns = %w[name title caption reason body].intersection(@model.column_names)
      if query[:query].present? && columns.any?
        pattern = "%#{@model.sanitize_sql_like(query[:query].to_s.first(200))}%"
        scope = scope.where(columns.map { |column| "#{@model.connection.quote_column_name(column)} ILIKE :term" }.join(" OR "), term: pattern)
      end
      page = [query[:page].to_i, 1].max
      total = scope.count
      { "records" => scope.offset((page - 1) * 25).limit(25).map { |record| present(record) },
        "total" => total, "page" => page, "next_page" => (page + 1 if page * 25 < total) }
    end

    def detail(_key, id)
      { "record" => present(@model.find(id)) }
    rescue ActiveRecord::RecordNotFound
      raise RemoteClient::NotFound, "This record could not be found."
    end

    private

    def present(record)
      data = record.attributes.slice("id", *@resource.fetch(:fields))
      product = record.respond_to?(:commerce_product) ? record.commerce_product : nil
      merchant = record.respond_to?(:commerce_merchant) ? record.commerce_merchant : nil
      order = record.respond_to?(:commerce_order) ? record.commerce_order : nil
      data["title"] = product&.title.presence || (record.name if record.respond_to?(:name)).presence ||
        (record.caption.to_s.first(100) if record.respond_to?(:caption)).presence ||
        merchant&.display_name.presence || @resource[:label].singularize
      data["subtitle"] = merchant&.display_name.presence || ("Order #{order.order_id}" if order) ||
        (record.reason.to_s.humanize if record.respond_to?(:reason))
      data
    end
  end
end
