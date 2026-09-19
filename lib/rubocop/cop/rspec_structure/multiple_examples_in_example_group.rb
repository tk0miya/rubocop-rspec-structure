# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecStructure
      # Checks that an example group (`describe`, `context`, `feature`, ...)
      # does not directly nest more than one example. Under BDD's
      # Given-When-Then structure, a group's own body is a single
      # precondition — the subject under `describe`, or the "Given"/"When"
      # under `context` — so it should set up exactly one "Then". Two
      # examples sitting side by side in the same group with nothing
      # distinguishing them push the reader to guess whether they share one
      # condition (so they belong in a single example) or cover different
      # conditions (so they belong in separate `context` blocks).
      #
      # Only examples nested directly in the group's own body count;
      # examples inside a nested group are that group's concern, not this
      # one's.
      #
      # Unlike `Metrics`-style cops, this rule has no `Max` to raise:
      # "more than one" is always an offense, by design — the point is to
      # force a merge or a split, not to let a project dial in a bigger
      # number.
      #
      # @example
      #   # bad
      #   describe User do
      #     it "allows deletion" do
      #     end
      #
      #     it "allows editing" do
      #     end
      #   end
      #
      #   # good - merged into one example
      #   context "when the user is an admin" do
      #     it "allows deletion and editing" do
      #     end
      #   end
      #
      #   # good - split into separate contexts
      #   describe User do
      #     context "when the user is an admin" do
      #       it "allows deletion" do
      #       end
      #     end
      #
      #     context "when the user is a viewer" do
      #       it "allows editing" do
      #       end
      #     end
      #   end
      #
      #   # good - nested groups are fine; each one still has a single example
      #   context "when the user is an admin" do
      #     context "and the record is archived" do
      #       it "still allows deletion" do
      #       end
      #     end
      #
      #     context "and the record is active" do
      #       it "allows deletion" do
      #       end
      #     end
      #   end
      class MultipleExamplesInExampleGroup < Base
        include RuboCop::RSpec::Language

        MSG = "This example group has %<total>d examples directly nested. Merge them into a " \
              "single example, or add a nested context for each example to distinguish " \
              "their conditions."

        # Used when `rubocop-rspec`'s own default config (which defines the
        # `describe`/`context`/`it` DSL aliases) has not been merged, e.g.
        # because a project lists only this gem under `plugins:`.
        DEFAULT_LANGUAGE_CONFIG = {
          "ExampleGroups" => {
            "Regular" => %w[describe context feature example_group],
            "Focused" => %w[fdescribe fcontext ffeature],
            "Skipped" => %w[xdescribe xcontext xfeature]
          },
          "Examples" => {
            "Regular" => %w[it specify example],
            "Focused" => %w[fit fspecify fexample],
            "Skipped" => %w[xit xspecify xexample skip],
            "Pending" => ["pending"]
          }
        }.freeze

        def on_new_investigation #: void
          super
          RuboCop::RSpec::Language.config = config["RSpec"]&.fetch("Language", nil) || DEFAULT_LANGUAGE_CONFIG
        end

        # @rbs node: RuboCop::AST::BlockNode
        def on_block(node) #: void
          return unless example_group?(node)

          examples = direct_examples(node)
          return if examples.size <= 1

          add_offense(node.send_node, message: format(MSG, total: examples.size))
        end

        private

        # Only the block's own top-level statements count. A body with a
        # single statement isn't wrapped in a `begin` node, so that case is
        # handled separately from the multi-statement one.
        # @rbs node: RuboCop::AST::BlockNode
        def direct_examples(node) #: Array[RuboCop::AST::Node]
          body = node.body
          return [] unless body

          statements = body.begin_type? ? body.children : [body]
          statements.select { _1.block_type? && example?(_1) }
        end
      end
    end
  end
end
