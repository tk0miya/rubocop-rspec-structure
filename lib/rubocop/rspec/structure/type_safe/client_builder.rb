# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # The interface Client, Cache, and NullClient all satisfy
        # structurally rather than through a shared ancestor: anything that
        # can answer `nouls`.
        # @rbs!
        #   interface _Client
        #     def nouls: (Array[NoulQuestion] items) -> Hash[String, Float]
        #   end

        # Builds the client a cop uses to ask Jev questions: a NullClient
        # when there's no API key configured, a plain Client otherwise, or
        # a Cache-wrapped Client when CacheEnabled (the default, resolved
        # from `cop_config`). Isolating this from the cop lets it be built
        # and tested on its own, independent of any particular cop's other
        # concerns.
        class ClientBuilder
          # @rbs cop_config: Hash[String, untyped]
          def initialize(cop_config) #: void
            @cop_config = cop_config
          end

          def build #: _Client
            api_key = type_safe_api_key
            return NullClient.new unless api_key

            # Named once here, rather than calling `cop_config.fetch("Model", ...)`
            # a second time below, since it's part of both the Client and the
            # Cache wrapping it (part of its cache key).
            model = cop_config.fetch("Model", "jev-latest")
            client = Client.new(api_key:, model:, timeout: cop_config.fetch("JevTimeoutSeconds", 5))
            return client unless cop_config.fetch("CacheEnabled", true)

            # `nil` when `CachePath` is unconfigured, so `Cache` resolves its own
            # default location (a machine-wide, per-user path) instead of this
            # builder knowing anything about where a cache file "should" live.
            Cache.new(client:, model:, path: cache_path)
          end

          private

          attr_reader :cop_config #: Hash[String, untyped]

          def type_safe_api_key #: String?
            key = ENV.fetch("TYPESAFE_API_KEY", nil)
            key.nil? || key.empty? ? nil : key
          end

          # Same env-wins-over-config precedence as
          # `ConfigOverride#env_or_config`, reimplemented here rather than
          # shared: that module assumes an including `RuboCop::Cop::Base`'s
          # ambient `cop_config`, which this plain builder deliberately
          # isn't.
          def cache_path #: String?
            ENV.fetch("RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH", nil) || cop_config["CachePath"]
          end
        end
      end
    end
  end
end
