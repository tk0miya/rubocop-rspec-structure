# frozen_string_literal: true

module RuboCop
  module RSpec
    module Structure
      # Every cop that includes `RuboCop::RSpec::Language` needs
      # `RuboCop::RSpec::Language.config` populated for its node matchers
      # (`example?`, `spec_group?`, ...) to work at all. `rubocop-rspec`
      # supplies it via `config["RSpec"]["Language"]` when loaded as a
      # plugin; raise a clear, actionable error if it's missing instead of
      # running against incomplete data.
      # @rbs module-self RuboCop::Cop::Base
      module RequiresRuboCopRspec
        def on_new_investigation #: void
          super

          language_config = config["RSpec"]&.fetch("Language", nil)
          unless language_config
            raise RuboCop::RSpec::Structure::Error,
                  "#{cop_name} requires \"rubocop-rspec\" to also be listed under `plugins:` " \
                  "in .rubocop.yml."
          end

          RuboCop::RSpec::Language.config = language_config
        end
      end
    end
  end
end
