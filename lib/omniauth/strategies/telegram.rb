require 'omniauth'
require 'openssl'
require 'base64'

module OmniAuth
  module Strategies
    class Telegram
      include OmniAuth::Strategy

      args %i[bot_name bot_secret]

      option :name, 'telegram'
      option :bot_name, nil
      option :bot_secret, nil
      option :button_config, {}
      option :version, '22'
      option :expiration_time, nil

      REQUIRED_FIELDS = %w[id hash].freeze
      HASH_FIELDS     = %w[auth_date first_name id last_name photo_url username].freeze

      def self.calculate_signature(secret, params)
        secret = OpenSSL::Digest.digest('SHA256', secret)
        signature = generate_comparison_string(params)
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('SHA256'), secret, signature)
      end

      def self.generate_comparison_string(params)
        (params.keys & HASH_FIELDS).sort.map { |field| '%s=%s' % [field, params[field]] }.join("\n")
      end

      def request_phase
        html = <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
            <title>Telegram Login</title>
          </head>
          <body>
        HTML

        data_attrs = options.button_config.map { |k, v| "data-#{k}=\"#{v}\"" }.join(" ")

        html << "<script async
              src=\"https://telegram.org/js/telegram-widget.js?#{options.version}\"
              data-telegram-login=\"#{options.bot_name}\"
              data-auth-url=\"#{callback_url}\"
        #{data_attrs}></script>"

        html << <<-HTML
          </body>
          </html>
        HTML

        Rack::Response.new(html, 200, 'content-type' => 'text/html').finish
      end

      def callback_phase
        if (error = check_errors)
          fail!(error)
        else
          super
        end
      end

      uid do
        request.params['id']
      end

      info do
        {
          name: full_name(request.params['first_name'], request.params['last_name']),
          nickname: request.params['username'],
          first_name: request.params['first_name'],
          last_name: request.params['last_name'],
          image: request.params['photo_url']
        }
      end

      extra do
        {
          auth_date: Time.at(request.params['auth_date'].to_i)
        }
      end

      private

      def check_errors
        return :field_missing unless check_required_fields
        return :signature_mismatch unless check_signature
        return :session_expired unless check_session
      end

      def full_name(first_name, last_name = nil)
        [first_name, last_name].compact.join(' ')
      end

      def check_required_fields
        REQUIRED_FIELDS.all? { |f| request.params.include?(f) }
      end

      def check_signature
        request.params['hash'] == self.class.calculate_signature(options.bot_secret, request.params)
      end

      def check_session
        return true if options.expiration_time.nil?

        Time.now.to_i - request.params['auth_date'].to_i <= options.expiration_time.to_i
      end
    end
  end
end
