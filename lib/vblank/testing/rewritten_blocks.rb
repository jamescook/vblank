# frozen_string_literal: true

module VBlank
  module Testing
    # A test's game block is run through DSL::PlainRuby as a game's is, so a test can say what it
    # means in normal Ruby. A test starts its game on a Builder by hand, with `instance_eval`,
    # which is the one place every such block passes. The checks stay out: a test names its own
    # helpers and fixtures, and a game has no reason to.
    module RewrittenBlocks
      def instance_eval(*given, &block)
        return super if !given.empty? || block.nil? || !DSL::PlainRuby.rewritable?(block)

        super(&DSL::PlainRuby.rewrite(block, checked: false))
      end
    end
  end
end

VBlank::Builder.prepend(VBlank::Testing::RewrittenBlocks)
