require "ostruct"

module Admin
  module Pagination
    extend ActiveSupport::Concern

    def paginate(scope, per_page: 20)
      per_page = params[:per_page].to_i if [20, 50, 100].include?(params[:per_page].to_i)
      page = [params[:page].to_i, 1].max
      total = scope.count
      page = [page, [(total.to_f / per_page).ceil, 1].max].min
      offset = (page - 1) * per_page
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
