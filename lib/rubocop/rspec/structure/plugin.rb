# frozen_string_literal: true

require "lint_roller"
require "pathname"

module RuboCop
  module RSpec
    module Structure
      # Integrates this gem with RuboCop's plugin system (via lint_roller),
      # the same mechanism rubocop-rspec itself uses. Referenced from the
      # gemspec's `default_lint_roller_plugin` metadata, so listing this gem
      # under `plugins:` in `.rubocop.yml` is enough to load it.
      class Plugin < LintRoller::Plugin
        def about #: LintRoller::About
          LintRoller::About.new(
            name: "rubocop-rspec-structure",
            version: VERSION,
            homepage: "https://github.com/tk0miya/rubocop-rspec-structure",
            description: "Checks the structure of RSpec examples."
          )
        end

        # @rbs context: untyped
        def supported?(context) #: bool
          context.engine == :rubocop
        end

        # @rbs _context: untyped
        def rules(_context) #: LintRoller::Rules
          project_root = Pathname.new(File.dirname(__FILE__)).join("../../../..")

          LintRoller::Rules.new(
            type: :path,
            config_format: :rubocop,
            value: project_root.join("config/default.yml")
          )
        end
      end
    end
  end
end
