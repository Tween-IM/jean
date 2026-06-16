# frozen_string_literal: true

# Permits a set of attributes from the request body, accepting BOTH the
# Rails-conventional wrapped form (e.g. `upload: { filename: "..." }`) and
# the flat top-level form (e.g. `{ filename: "..." }`).
#
# This exists because the deployed Flutter client sends flat bodies while
# the existing tests and the original controller contract use wrapped
# bodies. Rather than break either side, we accept both and normalize to
# an ActionController::Parameters instance containing the merged keys.
#
# Usage in a controller:
#   def upload_params
#     SocialParams.permit(params, wrapper: :upload, keys: %i[filename byte_size checksum content_type])
#   end
module SocialParams
  module_function

  def permit(params, wrapper:, keys:, array_keys: [], hash_keys: [])
    source =
      if params[wrapper].is_a?(ActionController::Parameters) || params[wrapper].is_a?(Hash)
        params[wrapper]
      else
        params
      end

    permitted_keys = keys + array_keys + hash_keys
    source.permit(*permitted_keys)
  end
end
