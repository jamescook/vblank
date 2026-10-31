# frozen_string_literal: true

module VBlank
  module DSL
    # The result of comparing two Values: a yes/no test the program branches on.
    # Branch with `.then` (and an optional `.else`). Combine tests with & (both)
    # and | (either) — Ruby's `&&`/`||` can't be overloaded, so the single-character
    # forms are the ones that build a combined Condition.
    #
    # Always branch with `.then`, never a native Ruby `if`. `if (x > 5)` looks
    # right, but a Condition is *truthy* to Ruby, so its body would emit
    # unconditionally at build time with the comparison silently ignored — no error,
    # just a ROM that always runs the branch.
    class Condition
      Build = IR::Build

      def initialize(builder, node)
        @builder = builder
        @node = node
        @source = self.class.author_source
        # Enter the builder's "pending" set on birth; #then / & / | take us back out
        # once we're used. Whatever never leaves was built and never branched on —
        # the fingerprint of a comparison dropped into a native `if`.
        builder.track_condition(self)
      end

      # The IR value node for the test (a comparison binop).
      attr_reader :node

      # Where the author built this Condition ("file.rb:line"), or nil if it can't be
      # pinned down — used to point the orphaned-Condition diagnostic at their code.
      attr_reader :source

      # Both tests must hold. Parenthesize the operands — `&` binds tighter than the
      # comparisons: (a > b) & (c < d).
      def &(other)
        compose(:and, other)
      end

      # Either test may hold: (a > b) | (c < d).
      def |(other)
        compose(:or, other)
      end

      # Run the block's statements only when the condition holds. Records an `if`
      # node carrying the block, the same shape the low-level if_* verbs build, and
      # returns a {Branch} so an `.else { ... }` can chain onto it.
      #
      # `estimate:` does nothing but earn a warning (see Builder#record_estimate_line).
      def then(estimate: nil, &block)
        unless block
          raise ArgumentError, "(cond).then needs a block: (x > 0).then { ... }"
        end

        @builder.consume_condition(self)
        @builder.record_estimate_line(estimate)
        if_node = @builder.record_conditional(@node, &block)
        Branch.new(@builder, if_node)
      end

      # The same branch taken a step at a time, for normal Ruby's `if` (see PlainRuby), whose
      # sides are not blocks. Statements recorded until #close_branch go in it.
      def open_branch
        @builder.consume_condition(self)
        @builder.open_branch(@node)
      end

      # ...and its other side, with the node #open_branch gave back.
      def open_other_branch(if_node) = @builder.open_other_branch(if_node)

      def close_branch = @builder.close_branch

      # A loop on this test, stopping once it holds, taken a step at a time as a branch is.
      def open_repeat(most_passes)
        @builder.consume_condition(self)
        @builder.open_repeat(most_passes, @node)
      end

      def close_repeat = @builder.close_repeat

      def hidden_variable = @builder.hidden_variable

      # The opposite test. A Ruby `!` on a Condition would otherwise answer plain false, and
      # the comparison would be lost with no word said.
      def !
        @builder.consume_condition(self)
        Condition.new(@builder, Build.binop(:==, @node, Build.int(0)))
      end

      # This test is not needed after all: a plain value beside it decided the answer
      # (see PlainRubySteps.both). Marks it used, and answers false.
      def discard
        @builder.consume_condition(self)
        false
      end

      private

      # Build a combined Condition. Both sides must be Conditions — you compose
      # yes/no tests, not raw numbers (a bare number has no branch meaning here).
      # Both operands are folded into the new one, so both are now used.
      def compose(op, other)
        unless other.is_a?(Condition)
          raise ArgumentError,
                "compose conditions with & and |, e.g. (a > b) & (c < d) — got #{other.class}"
        end

        @builder.consume_condition(self)
        @builder.consume_condition(other)
        Condition.new(@builder, Build.binop(op, @node, other.node))
      end

      # The first call-stack frame outside the library — the author's line — as
      # "path:line", or nil if every frame is internal.
      def self.author_source = Messages::AuthorSource.author_source
    end
  end
end
