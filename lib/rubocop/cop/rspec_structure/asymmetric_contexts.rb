# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecStructure
      # Checks that a `context` describing one branch of an externally
      # observable behavioral condition has a sibling context for its
      # natural counterpart, among the `context` blocks nested directly
      # under the same parent group.
      #
      # A lone context with no siblings at all is always flagged
      # mechanically, with no Jev call: `context` is a statement that
      # execution branches on some condition, so a context that stands
      # alone either has a missing counterpart, or was never a real branch
      # to begin with and shouldn't be wrapped in `context` at all.
      #
      # With two or more sibling contexts, each one is judged individually:
      # is its natural complementary branch represented, exactly or
      # loosely, by any of its siblings? That judgment is inherently
      # semantic — no keyword list can decide it — so it is made only by
      # Jev (TypeSafe AI's System One model). This cop has no deterministic
      # fallback for that case, and is a no-op once there are two or more
      # siblings without `TYPESAFE_API_KEY` set.
      #
      # Only direct siblings are compared. A counterpart implemented
      # elsewhere — a different `describe`, a different file — does not
      # satisfy this check: the point is that a behavioral branch should
      # be represented in the same context tree, not merely covered
      # somewhere in the suite.
      #
      # This cop does not check for exhaustive coverage of a multi-valued
      # condition (e.g. a 3-way enum with only two values tested), and does
      # not decide where in the tree a missing branch belongs, or whether
      # existing siblings should be nested more deeply. Several offenses
      # firing together on the same flat sibling list is this cop's way of
      # signaling that the tree may need restructuring; it only surfaces
      # the individual gaps, not the restructuring itself.
      #
      # A group that also generates `context` blocks dynamically — e.g. a
      # `TYPES.each do |type| context "..." do ... end end` loop sitting
      # alongside a single static `context` — skips only the solitary
      # check for that context: its real siblings live inside the loop
      # body, invisible to a per-statement AST walk, so declaring it alone
      # would be wrong. Two or more static siblings are still compared to
      # each other by Jev as usual, whether or not such a loop is also
      # present: that comparison only looks at the static siblings named
      # in it, so an unrelated loop elsewhere in the same group doesn't
      # make it any less meaningful.
      #
      # @example
      #   # bad - "when the user is logged in" is missing
      #   describe "#dashboard" do
      #     context "when the user is not logged in" do
      #       it "redirects to the login page" do
      #       end
      #     end
      #   end
      #
      #   # good
      #   describe "#dashboard" do
      #     context "when the user is not logged in" do
      #       it "redirects to the login page" do
      #       end
      #     end
      #
      #     context "when the user is logged in" do
      #       it "renders the dashboard" do
      #       end
      #     end
      #   end
      #
      #   # bad - a lone context has no counterpart to compare against
      #   describe "#dashboard" do
      #     context "when the user is not logged in" do
      #       it "redirects to the login page" do
      #       end
      #     end
      #   end
      class AsymmetricContexts < Base
        include RuboCop::RSpec::Language
        include RuboCop::RSpec::Structure::RequiresRuboCopRspec
        include RuboCop::RSpec::Structure::JevIntegration
        include RuboCop::RSpec::Structure::DiffScoping

        MSG_SOLITARY =
          "This is the only context directly nested here. If it expresses a real " \
          "condition, add a sibling context for the complementary case; if there is " \
          "no real condition, remove the context wrapper and flatten these examples " \
          "into the parent group."

        MSG_ASYMMETRIC =
          "This context describes a condition with no sibling context for its " \
          "natural counterpart (estimated probability: %<probability>.2f). Add a " \
          "`context` for the complementary case, or move existing coverage of it " \
          "into this tree."

        JEV_INSTRUCTIONS =
          "The state describes one `context` block (the TARGET) and lists its sibling " \
          "`context` blocks, all nested directly under the same parent group in an " \
          "RSpec spec file. Judge whether the target implies some externally observable " \
          "behavioral condition (e.g. a boolean state, an enum value, a success/failure " \
          "outcome) for which NO sibling — individually or collectively — represents " \
          "the natural complementary/opposite branch of that same condition. A sibling " \
          "satisfies the complement even if it isn't an exact mirror of the target's " \
          "wording (e.g. a general 'invalid input' sibling can satisfy the complement " \
          "of a specific 'valid input' target; several distinct failure-mode siblings " \
          "can jointly satisfy the complement of one 'succeeds' target). Do not " \
          "require an exact one-to-one phrasing match — judge by whether the " \
          "outcome/condition space is actually covered somewhere among the siblings. " \
          "Answer yes only when the complementary branch is truly absent, not merely " \
          "phrased differently or split across siblings. Answer no when: the target " \
          "has no clear complementary branch to begin with (a standalone scenario, one " \
          "implementation variant among several non-exclusive options, or an outcome " \
          "elaboration with no condition); or the target is one case in a larger " \
          "enumeration where at least one other value of the same axis is already " \
          "present (a 3+-value enum with only 2 values tested is a coverage/" \
          "completeness question, out of scope here, not asymmetry). Base your " \
          "judgment only on externally observable behavior implied by the wording, " \
          "never on internal implementation details you cannot see."

        JEV_CRITERIA = {
          "true" => "The target implies an externally observable condition with a " \
                    "natural complementary/opposite branch (success vs failure, " \
                    "present vs absent, logged-in vs not logged-in, valid vs invalid), " \
                    "and no sibling, alone or together, represents that complementary " \
                    "branch even loosely.",
          "false" => "Either (a) some sibling, or some combination of siblings, " \
                     "already represents the target's complementary branch (even if " \
                     "phrased differently, or split into several more specific " \
                     "siblings), or (b) the target doesn't clearly imply a binary/" \
                     "complementary condition in the first place (a standalone " \
                     "scenario, a named variant among parallel implementation " \
                     "choices, or one already-represented value within a larger " \
                     "multi-value enumeration)."
        }.freeze

        # Literal method-name match, independent of `RSpec::Language`
        # config, following `rubocop-rspec`'s own `RSpec::ContextWording`
        # precedent: `Language`'s `ExampleGroups` lumps `describe`/
        # `context`/`feature` together, with no way to isolate "context"
        # alone.
        #
        # `def_node_matcher` defines these at runtime, invisibly to
        # rbs-inline, so their signatures are declared explicitly here.
        # @rbs!
        #   def context_family?: (untyped node) -> bool
        #   def context_with_description: (untyped node) -> untyped

        def_node_matcher :context_family?, <<~PATTERN
          (block (send #rspec? {:context :fcontext :xcontext} ...) ...)
        PATTERN

        # Same method-name match as `context_family?`, but additionally
        # requires a plain (non-interpolated) string description: the
        # `str` node type excludes `dstr` (interpolated strings) on its own.
        def_node_matcher :context_with_description, <<~PATTERN
          (block (send #rspec? {:context :fcontext :xcontext} $(str ...) ...) ...)
        PATTERN

        # @rbs node: RuboCop::AST::BlockNode
        def on_block(node) #: void
          return unless spec_group?(node)

          siblings = direct_context_siblings(node)
          return if siblings.empty?

          if siblings.size == 1
            return if dynamic_context_generator?(node)

            solitary = siblings.first #: RuboCop::AST::BlockNode
            add_offense(solitary.send_node, message: MSG_SOLITARY)
            return
          end

          check_each_sibling(node, siblings)
        end

        private

        # Only the block's own top-level statements count, and only those
        # that are themselves `context`-family blocks — same
        # begin_type?/single-statement split as
        # MultipleExamplesInGroup#direct_examples. Description text isn't
        # read here, so an interpolated (dstr) sibling still counts toward
        # this structural count.
        # @rbs node: RuboCop::AST::BlockNode
        def direct_context_siblings(node) #: Array[RuboCop::AST::BlockNode]
          top_level_statements(node).select { _1.block_type? && context_family?(_1) } #: Array[RuboCop::AST::BlockNode]
        end

        # A top-level statement that is itself some other block call (an
        # `each`-style iteration, typically) and wraps a `context`-family
        # block somewhere inside it, however deeply nested, is treated as
        # generating an unknown number of contexts at runtime.
        # @rbs node: RuboCop::AST::BlockNode
        def dynamic_context_generator?(node) #: bool
          top_level_statements(node).any? do |stmt|
            stmt.block_type? && !context_family?(stmt) &&
              stmt.each_descendant(:block).any? { context_family?(_1) }
          end
        end

        # A body with a single statement isn't wrapped in a `begin` node,
        # so that case is handled separately from the multi-statement one.
        # @rbs node: RuboCop::AST::BlockNode
        def top_level_statements(node) #: Array[RuboCop::AST::Node]
          body = node.body
          return [] unless body

          body.begin_type? ? body.children : [body]
        end

        # @rbs node: RuboCop::AST::BlockNode
        # @rbs siblings: Array[RuboCop::AST::BlockNode]
        def check_each_sibling(node, siblings) #: void
          return if out_of_scope?(node)

          comparable = siblings.select { context_with_description(_1) }

          comparable.each do |target|
            others = comparable - [target]
            probability = jev_probability(
              state_for(target, others), instructions: JEV_INSTRUCTIONS, criteria: JEV_CRITERIA
            )
            next if probability.nil? || probability < cop_config.fetch("JevThreshold", 0.7)

            add_offense(target.send_node, message: format(MSG_ASYMMETRIC, probability:))
          end
        end

        # @rbs target: RuboCop::AST::BlockNode
        # @rbs others: Array[RuboCop::AST::BlockNode]
        def state_for(target, others) #: String
          lines = ["Target context: #{description_text(target)}"]
          if others.empty?
            lines << "Sibling contexts in the same tree: (none)"
          else
            lines << "Sibling contexts in the same tree:"
            others.each_with_index { |o, i| lines << "#{i + 1}. #{description_text(o)}" }
          end
          lines.join("\n")
        end

        # Re-matching is cheap, and lets `context_with_description`'s own
        # capture (declared `untyped`, since rbs-inline can't see through
        # `def_node_matcher`) supply the value instead of re-deriving it
        # from a `first_argument` that a static type can't narrow to
        # `StrNode` on its own. Every caller of this method has already
        # confirmed the match, so this is never nil in practice.
        # @rbs sibling: RuboCop::AST::BlockNode
        def description_text(sibling) #: String
          context_with_description(sibling).value
        end

        # Checked at file granularity, deliberately coarser than
        # `ConditionInExample`'s line-precise `changed?`: the judgment for
        # any one sibling depends on every sibling in `node`, including one
        # deleted outright elsewhere in the file, which leaves no line of
        # its own for a line-precise check to find.
        # @rbs node: RuboCop::AST::BlockNode
        def out_of_scope?(node) #: bool
          return false if check_scope == "full"

          path = node.location.expression.source_buffer.name
          !diff_scope.changed_file?(path)
        end
      end
    end
  end
end
