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
        include RuboCop::RSpec::Structure::JevIntegration
        include RuboCop::RSpec::Structure::DiffScoping

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

        # Every description this cop wants Jev's semantic judgment on is
        # collected here instead of asked about immediately, so the whole
        # file's worth of them can go out as a single batched call — see
        # `check_descriptions`, called once this file's traversal
        # finishes.
        def on_new_investigation #: void
          super
          @descriptions = []
        end

        def on_investigation_end #: void
          super
          check_descriptions
        end

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

        attr_reader :descriptions #: Array[Hash[Symbol, untyped]]

        # @rbs block_node: RuboCop::AST::BlockNode
        # @rbs description_node: RuboCop::AST::StrNode
        # @rbs text: String
        def check(block_node, description_node, text) #: void
          return if out_of_scope?(block_node)

          if heuristic.condition?(text)
            add_offense(description_node, message: MSG)
            return
          end

          descriptions << { id: descriptions.size.to_s, state: text, description_node: }
        end

        # Runs once per file, after every `it`/`example` has been visited:
        # turns the collected descriptions into a single `jev_probabilities`
        # call, then walks the results back onto their own description
        # nodes.
        def check_descriptions #: void
          entries = descriptions
          return if entries.empty?

          threshold = cop_config.fetch("JevThreshold", 0.6)
          items = entries.map do |entry|
            RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(
              id: entry[:id], state: entry[:state], instructions: JEV_INSTRUCTIONS, criteria: JEV_CRITERIA
            )
          end
          probabilities = jev_probabilities(items)

          entries.each do |entry|
            probability = probabilities[entry[:id]]
            next if probability.nil? || probability < threshold

            add_offense(entry[:description_node], message: format(MSG_WITH_PROBABILITY, probability:))
          end
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
      end
    end
  end
end
