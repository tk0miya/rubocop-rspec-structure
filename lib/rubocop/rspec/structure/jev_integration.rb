# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      # Asking Jev a single yes/no question and getting back a calibrated
      # probability: building the API client (optionally cache-wrapped),
      # resolving the API key/model/cache path from config or environment,
      # and turning a client error into whatever `OnJevError` asks for.
      #
      # `check_scope`/`diff_scope` (whether a node is worth the cost of an
      # API call at all) are a separate responsibility — see
      # `DiffScoping` — since they have nothing to do with Jev's API
      # itself; each including cop composes the two independently.
      # @rbs module-self RuboCop::Cop::Base
      module JevIntegration
        include ConfigOverride

        # @rbs @type_safe_client: untyped

        private

        # @rbs state: String
        # @rbs instructions: String
        # @rbs criteria: Hash[String, String]?
        def jev_probability(state, instructions:, criteria: nil) #: Float?
          api_key = type_safe_api_key
          return nil unless api_key

          type_safe_client(api_key).noul(state:, instructions:, criteria:)
        rescue RuboCop::RSpec::Structure::TypeSafe::Error => e
          handle_jev_error(e)
          nil
        end

        # @rbs error: StandardError
        def handle_jev_error(error) #: void
          case cop_config.fetch("OnJevError", "skip")
          when "raise"
            raise error
          when "warn"
            warn("rubocop-rspec-structure: TypeSafe API error: #{error.message}")
          end
        end

        # @rbs api_key: String
        def type_safe_client(api_key) #: untyped
          @type_safe_client ||= build_type_safe_client(api_key)
        end

        # @rbs api_key: String
        def build_type_safe_client(api_key) #: untyped
          # Named once here, rather than calling `cop_config.fetch("Model", ...)`
          # a second time below, since it's part of both the Client and the
          # Cache wrapping it (part of its cache key).
          model = cop_config.fetch("Model", "jev-latest")
          client = RuboCop::RSpec::Structure::TypeSafe::Client.new(
            api_key:, model:, timeout: cop_config.fetch("JevTimeoutSeconds", 5)
          )
          return client unless cop_config.fetch("CacheEnabled", true)

          # `nil` when `CachePath` is unconfigured, so `Cache` resolves its own
          # default location (a machine-wide, per-user path) instead of this
          # mixin knowing anything about where a cache file "should" live.
          path = env_or_config("RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH", "CachePath", nil)
          RuboCop::RSpec::Structure::TypeSafe::Cache.new(client:, model:, path:)
        end

        def type_safe_api_key #: String?
          key = ENV.fetch("TYPESAFE_API_KEY", nil)
          key.nil? || key.empty? ? nil : key
        end
      end
    end
  end
end
