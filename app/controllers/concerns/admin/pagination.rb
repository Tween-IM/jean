require "ostruct"

module Admin
  module Pagination
    extend ActiveSupport::Concern

    def paginate(scope, per_page: 20)
      page = [params[:page].to_i, 1].max
      offset = (page - 1) * per_page

      total = scope.count
      records = scope.limit(per_page).offset(offset)

      total_pages = (total.to_f / per_page).ceil

      OpenStruct.new(
        records: records,
        current_page: page,
        total_pages: total_pages,
        total_count: total,
        limit_value: per_page
      )
    end
  end
end
