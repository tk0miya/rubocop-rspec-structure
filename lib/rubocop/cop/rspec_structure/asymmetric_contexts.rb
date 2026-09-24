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

        # Judges the target and each sibling against the same axis, checked
        # symmetrically in both directions: swapping which of two sibling
        # contexts is labeled TARGET must not change the verdict, since a
        # real asymmetry (or the lack of one) doesn't depend on that
        # labeling.
        JEV_INSTRUCTIONS =
          "The state describes one `context` block (the TARGET) and lists its sibling " \
          "`context` blocks, all nested directly under the same parent group in an " \
          "RSpec spec file. First decide whether the target varies on a real, " \
          "externally observable property that the behavior actually depends on, " \
          "rather than being incidental setup or fixture detail with no behavioral " \
          "branch of its own (e.g. which factory helper built a record). If the " \
          "target is such a detail, answer no immediately. Otherwise, name the " \
          "target's property/axis (e.g. login status, payment outcome, file format) " \
          "and the value it takes on that axis, then check every sibling for a " \
          "DIFFERENT value on that SAME axis. A sibling satisfies this even if it " \
          "isn't an exact mirror of the target's wording — a strict opposite (valid " \
          "vs invalid) counts, and so does any other value of a multi-valued " \
          "property (a different file format, a different role). If some sibling " \
          "names another value on the same axis, the axis is already represented in " \
          "this group — answer no, regardless of whether that sibling is the exact " \
          "opposite. Answer yes only if no sibling touches the target's axis at " \
          "all. Apply this symmetrically: swapping which of two contexts is labeled " \
          "TARGET must yield the same answer for both, since both are checked " \
          "against the same axis. Examples: target 'with a valid coupon', sibling " \
          "'as a first-time buyer' — different axes (coupon validity vs customer " \
          "tenure), neither touches the other's axis, so yes for both directions. " \
          "target 'when the file type is CSV', sibling 'when the file type is " \
          "JSON' — the same axis (file format), with the sibling naming a " \
          "different value on it, so no for both directions. target 'using the " \
          "factory-built default user', sibling 'when rate limiting is enabled' — " \
          "the first is setup detail with no real axis (no); the second is a real " \
          "condition untouched by that detail (yes)."

        JEV_CRITERIA = {
          "true" => "The target varies on a real, externally observable behavioral " \
                    "axis, and no sibling names another value on that same axis.",
          "false" => "Either the target is only setup/fixture detail with no real " \
                     "behavioral axis of its own, or some sibling names another " \
                     "value — loosely worded is fine — on the same axis the " \
                     "target varies on."
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

        # Every target context this cop wants Jev's judgment on is
        # collected here instead of asked about immediately, so the whole
        # file's worth of them can go out as a single batched call — see
        # `check_contexts`, called once this file's traversal finishes.
        def on_new_investigation #: void
          super
          @contexts = []
        end

        def on_investigation_end #: void
          super
          check_contexts
        end

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

        # @rbs @client: RuboCop::RSpec::Structure::TypeSafe::_Client

        attr_reader :contexts #: Array[Hash[Symbol, untyped]]

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
            contexts << { id: contexts.size.to_s, state: state_for(target, others), target: }
          end
        end

        # Runs once per file, after every sibling group has been visited:
        # turns the collected contexts into a single `jev_probabilities`
        # call, then walks the results back onto their own target contexts.
        def check_contexts #: void
          entries = contexts
          return if entries.empty?

          threshold = cop_config.fetch("JevThreshold", 0.7)
          items = entries.map do |entry|
            RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(
              id: entry[:id], state: entry[:state], instructions: JEV_INSTRUCTIONS, criteria: JEV_CRITERIA
            )
          end
          probabilities = jev_probabilities(items)

          entries.each do |entry|
            probability = probabilities[entry[:id]]
            next if probability.nil? || probability < threshold

            add_offense(entry[:target].send_node, message: format(MSG_ASYMMETRIC, probability:))
          end
        end

        # Resolves a batch of independent Noul questions in one call. The
        # result is a `{id => probability}` hash. Returns `{}` when there's
        # no API key configured — `client` hands back a `NullClient` rather
        # than ever touching the network — or when the call errors and
        # `OnJevError` doesn't re-raise. The caller can't tell those two
        # "no answer" cases apart, by design: either way, there's nothing
        # to do but skip.
        # @rbs items: Array[RuboCop::RSpec::Structure::TypeSafe::NoulQuestion]
        def jev_probabilities(items) #: Hash[String, Float]
          return {} if items.empty?

          client.nouls(items)
        rescue RuboCop::RSpec::Structure::TypeSafe::Error => e
          handle_jev_error(e)
          {}
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

        def client #: RuboCop::RSpec::Structure::TypeSafe::_Client
          @client ||= RuboCop::RSpec::Structure::TypeSafe::ClientBuilder.new(cop_config).build
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
