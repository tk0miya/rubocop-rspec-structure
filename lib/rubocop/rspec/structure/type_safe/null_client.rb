# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      module TypeSafe
        # Null Object standing in for Client/Cache when no API key is
        # configured, satisfying the same `_Client` interface (see
        # ClientBuilder) so callers can always ask a client for judgments
        # without first checking whether one is actually available.
        class NullClient
          # rubocop:disable Lint/UnusedMethodArgument

          # @rbs items: Array[NoulQuestion]
          def nouls(items) #: Hash[String, Float]
            {}
          end

          # rubocop:enable Lint/UnusedMethodArgument
        end
      end
    end
  end
end
