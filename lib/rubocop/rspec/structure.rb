# frozen_string_literal: true

require_relative "structure/version"
require_relative "structure/type_safe/error"
require_relative "structure/type_safe/client"
require_relative "structure/type_safe/cache"
require_relative "structure/type_safe/null_client"
require_relative "structure/condition_heuristic"
require_relative "structure/git_diff_scope"
require_relative "structure/requires_rubocop_rspec"
require_relative "structure/config_override"
require_relative "structure/diff_scoping"
require_relative "structure/jev_integration"
require_relative "structure/plugin"

module RuboCop
  module RSpec
    module Structure
      class Error < StandardError; end
    end
  end
end
