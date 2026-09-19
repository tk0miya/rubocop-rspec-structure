# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecStructure
      # Checks that an example description does not contain an execution
      # condition (`〜の場合`, `〜のとき`, `when ...`) that belongs in a
      # surrounding `context` block instead.
      #
      # A keyword check runs first and is always on, at no cost. When it
      # finds nothing and a TypeSafe API key (`TYPESAFE_API_KEY`) is set,
      # the description is also judged semantically by Jev (TypeSafe's
      # System One model), which can catch paraphrased conditions the
      # keyword list misses. Without an API key, only the keyword check
      # runs — the presence of the API key is the only switch between the
      # two.
      #
      # @example
      #   # bad
      #   it "ユーザーが管理者権限を持っている場合、削除できる" do
      #   end
      #
      #   # good
      #   context "ユーザーが管理者権限を持っている場合" do
      #     it "削除できる" do
      #     end
      #   end
      class ConditionInExample < Base
        include RuboCop::RSpec::Language
        include RuboCop::RSpec::Structure::RequiresRuboCopRspec

        MSG = "Move the condition described here into a surrounding `context` block."
        MSG_WITH_PROBABILITY = "Move the condition described here into a surrounding `context` " \
                               "block (estimated probability: %<probability>.2f)."

        JEV_INSTRUCTIONS =
          "This text is an RSpec example description (the string passed to `it`). Does it " \
          "describe an execution condition or precondition (for example \"when the user is an " \
          "admin\" or \"ユーザーが管理者権限を持っている場合\") that should instead be extracted " \
          "into a surrounding `context` block, rather than describing only the action performed " \
          "or the outcome expected? A condition can be an explicit \"when\"/\"if\"/\"の場合\" " \
          "clause, or a plain qualifying clause that names the distinguishing scenario under " \
          "which the behavior differs (for example \"flags X when it contains Y\"), not just a " \
          "descriptive detail of the outcome itself."

        # Distinguishes a branching condition on a property of the INPUT (true) from a
        # clause that merely elaborates on the OUTCOME itself (false), even when neither
        # uses an explicit when/if/の場合 token.
        JEV_CRITERIA = {
          "true" => "Describes a condition, state, or precondition under which the example " \
                    'runs — either an explicit clause (e.g. contains "when ...", "if ...", ' \
                    '"の場合", "のとき") or a qualifying clause that names a property of the ' \
                    "INPUT that changes which behavior applies, with no explicit token " \
                    '(e.g. "flags a description containing an English keyword", where ' \
                    '"containing an English keyword" is a branching condition on the input, ' \
                    "not a description of the outcome).",
          "false" => "Describes only the action performed or the outcome expected, including " \
                     "a qualifying clause that merely elaborates on the OUTCOME itself with no " \
                     'branching condition on the input (e.g. "returns an error message ' \
                     'containing details", "returns a list containing only active users" — ' \
                     "both just describe what the result contains, not a condition under " \
                     "which the example runs)."
        }.freeze

        # @rbs @heuristic: RuboCop::RSpec::Structure::ConditionHeuristic
        # @rbs @type_safe_client: untyped

        # @rbs node: RuboCop::AST::BlockNode
        def on_block(node) #: void
          return unless example?(node)

          description_node = node.send_node.first_argument
          return unless description_node.is_a?(RuboCop::AST::StrNode)
          # `DstrNode` (interpolated strings) is a subclass of `StrNode` in
          # rubocop-ast, so the `is_a?` check above alone would let dstr
          # descriptions through. `str_type?` checks the exact node type
          # and correctly excludes them.
          return unless description_node.str_type?

          text = description_node.value
          return unless text.is_a?(String)
          return if text.empty?

          check(node, description_node, text)
        end

        private

        # @rbs block_node: RuboCop::AST::BlockNode
        # @rbs description_node: RuboCop::AST::StrNode
        # @rbs text: String
        def check(block_node, description_node, text) #: void
          return if out_of_scope?(block_node)

          if heuristic.condition?(text)
            add_offense(description_node, message: MSG)
            return
          end

          probability = jev_probability(text)
          return if probability.nil? || probability < cop_config.fetch("JevThreshold", 0.6)

          add_offense(description_node, message: format(MSG_WITH_PROBABILITY, probability:))
        end

        # @rbs node: RuboCop::AST::Node
        def out_of_scope?(node) #: bool
          return false if check_scope == "full"

          path = node.location.expression.source_buffer.name
          !diff_scope.changed?(path, node.first_line)
        end

        def heuristic #: RuboCop::RSpec::Structure::ConditionHeuristic
          @heuristic ||= RuboCop::RSpec::Structure::ConditionHeuristic.new(
            keywords: cop_config.fetch("ConditionKeywords", [])
          )
        end

        # @rbs text: String
        def jev_probability(text) #: Float?
          api_key = type_safe_api_key
          return nil unless api_key

          client = type_safe_client(api_key)
          client.noul(state: text, instructions: JEV_INSTRUCTIONS, criteria: JEV_CRITERIA)
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
          client = RuboCop::RSpec::Structure::TypeSafe::Client.new(
            api_key:, model:, timeout: cop_config.fetch("JevTimeoutSeconds", 5)
          )
          return client unless cop_config.fetch("CacheEnabled", true)

          RuboCop::RSpec::Structure::TypeSafe::Cache.new(client:, model:, path: cache_path)
        end

        def type_safe_api_key #: String?
          key = ENV.fetch("TYPESAFE_API_KEY", nil)
          key.nil? || key.empty? ? nil : key
        end

        def check_scope #: String
          env_or_config("RUBOCOP_RSPEC_STRUCTURE_CHECK_SCOPE", "CheckScope", "diff")
        end

        def diff_scope #: RuboCop::RSpec::Structure::GitDiffScope
          RuboCop::RSpec::Structure::GitDiffScope.for(diff_base:)
        end

        def diff_base #: String
          env_or_config("RUBOCOP_RSPEC_STRUCTURE_DIFF_BASE", "DiffBase", "auto")
        end

        # Used to build both the Client (its model param) and the Cache
        # wrapping it (part of its cache key), so it earns a name instead
        # of two identical `cop_config.fetch` calls.
        def model #: String
          cop_config.fetch("Model", "jev-latest")
        end

        def cache_path #: String
          env_or_config("RUBOCOP_RSPEC_STRUCTURE_CACHE_PATH", "CachePath", default_cache_path)
        end

        # A Jev judgment is a pure function of (description, prompt, model), so it is
        # equally valid for every project on this machine, not just the current one.
        # Following the XDG Base Directory Specification (rather than a path under
        # this project) lets that cache be shared across all of them.
        def default_cache_path #: String
          File.join(cache_home, "rubocop-rspec-structure", "jev_cache.json")
        end

        # Falls back to a project-relative path when the home directory can't be
        # resolved at all, e.g. a minimal container running as an arbitrary UID
        # with no matching passwd entry.
        def cache_home #: String
          xdg_cache_home = ENV.fetch("XDG_CACHE_HOME", nil)
          return xdg_cache_home unless xdg_cache_home.nil? || xdg_cache_home.empty?

          home = user_home
          return File.join(home, ".cache") unless home.nil? || home.empty?

          "tmp"
        end

        # Dir.home consults $HOME first, then falls back to the OS user database
        # (e.g. /etc/passwd), which is more robust than reading ENV["HOME"] alone.
        # It raises ArgumentError when neither resolves.
        def user_home #: String?
          Dir.home
        rescue ArgumentError
          nil
        end

        # A config value that can also be overridden by an environment variable,
        # which always wins when set. `cop_config[config_key]` (rather than
        # `#fetch`) also falls back to `default` when a project's `.rubocop.yml`
        # sets the key to an explicit nil, since RuboCop's config merging only
        # drops a nil override when the department default also declares the key.
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
