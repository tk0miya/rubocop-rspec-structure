# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      # A single, generic responsibility: resolve a config value that can
      # also be overridden by an environment variable, which always wins
      # when set. Used by `DiffScoping` (`CheckScope`/`DiffBase`).
      # @rbs module-self RuboCop::Cop::Base
      module ConfigOverride
        private

        # `cop_config[config_key]` (rather than `#fetch`) also falls back to
        # `default` when a project's `.rubocop.yml` sets the key to an
        # explicit nil, since RuboCop's config merging only drops a nil
        # override when the department default also declares the key.
        # @rbs env_var: String
        # @rbs config_key: String
        # @rbs default: untyped
        def env_or_config(env_var, config_key, default) #: untyped
          ENV.fetch(env_var, nil) || cop_config[config_key] || default
        end
      end
    end
  end
end
