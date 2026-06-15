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
            n: encode_bn(public_key.n),
            e: encode_bn(public_key.e)
          }]
        else
          []
        end

        render json: { keys: keys }, status: :ok
      end

      private

      def encode_bn(bn)
        hex = bn.to_s(16)
        hex = "0#{hex}" if hex.length.odd?
        Base64.urlsafe_encode64([hex].pack("H*"), padding: false)
      end
    end
  end
end
