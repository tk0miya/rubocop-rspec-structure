# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecStructure
      # Checks that a group block (`describe`, `context`, `feature`,
      # `shared_examples`, `shared_context`, ...) does not directly nest
      # more than one example. Under BDD's Given-When-Then structure, a
      # group's own body is a single precondition — the subject under
      # `describe`, the "Given"/"When" under `context`, or whatever
      # precondition its includer supplies under `shared_examples`/
      # `shared_context` — so it should set up exactly one "Then". Two
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
      #
      #   # bad - a shared group is checked the same as any other group
      #   shared_examples "a paginated collection" do
      #     it "returns the first page" do
      #     end
      #
      #     it "returns the total count" do
      #     end
      #   end
      class MultipleExamplesInGroup < Base
        include RuboCop::RSpec::Language
        include RuboCop::RSpec::Structure::RequiresRuboCopRspec

        MSG = "This block has %<total>d examples directly nested. Merge them into a " \
              "single example, or add a nested context for each example to distinguish " \
              "their conditions."

        # @rbs node: RuboCop::AST::BlockNode
        def on_block(node) #: void
          return unless spec_group?(node)

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
