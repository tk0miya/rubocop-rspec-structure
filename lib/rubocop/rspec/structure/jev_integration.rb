# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      # Asking Jev a batch of yes/no questions and getting back calibrated
      # probabilities: building the API client (optionally cache-wrapped),
      # resolving the API key/model/cache path from config or environment,
      # and turning a client error into whatever `OnJevError` asks for.
      #
      # `jev_probabilities` is a plain, synchronous bulk call — it neither
      # collects questions nor decides when a file's worth of them is
      # ready. Collecting candidates during the AST walk and deciding when
      # to flush them (typically from the cop's own `on_investigation_end`)
      # is the including cop's job, so that a cop's control flow is
      # readable from the cop alone, without tracing into this mixin to
      # see when an API call actually happens.
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

        # Resolves a batch of independent Noul questions in one call. Each
        # item is `{id:, state:, instructions:, criteria:}`; the result is
        # a `{id => probability}` hash. Returns `{}` when there's no API
        # key configured — `type_safe_client` hands back a `NullClient`
        # rather than ever touching the network — or when the call errors
        # and `OnJevError` doesn't re-raise. The caller can't tell those
        # two "no answer" cases apart, by design: either way, there's
        # nothing to do but skip.
        # @rbs items: Array[Hash[Symbol, untyped]]
        def jev_probabilities(items) #: Hash[String, Float]
          return {} if items.empty?

          type_safe_client.nouls(items)
        rescue RuboCop::RSpec::Structure::TypeSafe::Error => e
          handle_jev_error(e)
          {}
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

        def type_safe_client #: untyped
          @type_safe_client ||= build_type_safe_client
        end

        def build_type_safe_client #: untyped
          api_key = type_safe_api_key
          return RuboCop::RSpec::Structure::TypeSafe::NullClient.new unless api_key

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
