# frozen_string_literal: true

module Api
  module WellKnown
    class JwksController < ApplicationController
      def jwks
        public_key = TepTokenService.public_key

        keys = if public_key
          [{
            kty: "RSA",
            alg: "RS256",
            use: "sig",
            kid: TMCP.config[:jwt_key_id],
            n: Base64.urlsafe_encode64(public_key.n.to_s(2), padding: false),
            e: Base64.urlsafe_encode64(public_key.e.to_s(2), padding: false)
          }]
        else
          []
        end

        render json: { keys: keys }, status: :ok
      end
    end
  end
end
