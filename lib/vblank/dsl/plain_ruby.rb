# frozen_string_literal: true

require "prism"

module VBlank
  module DSL
    # A game block written in normal Ruby.
    #
    # A block runs once, while the game is built, to record what the game will do. Ruby lets
    # nobody change what `if`, `&&` or `x = 1` mean, so the ordinary DSL spells them `.then`,
    # `&` and `set!`. This reads the block's own source with Prism and writes those few
    # constructs out as calls, and runs that instead. Everything else in the block, the verbs
    # above all, is left as it was written.
    #
    # NOTHING HERE GUESSES A TYPE. Whether `if hp > 0` is a test for the game or for the build
    # cannot be read off the source, so each construct becomes a small step (PlainRubySteps)
    # that looks at the value as the block runs: `if console == :gbc` stays plain Ruby.
    #
    # A BRANCH'S CODE STAYS WHERE IT WAS WRITTEN, inside parentheses in a real Ruby `if`, and is
    # never moved into a block. So the locals it sets outlive it and every line keeps its
    # number, which is what makes an error name the author's own line.
    module PlainRuby
      # Something a game block cannot do, said in plain words before the game is built.
      class Refused < BuildError; end

      module_function

      # +block+ again, as a proc that runs the rewritten source. It closes over what +block+
      # closed over, so the game's own constants and locals still resolve. +allow+ names
      # libraries the block may use, on the author's word that they are safe here.
      #
      # THIS RUNS AS THE GAME IS DECLARED, because the block's binding is only there to read until
      # a game is made shareable between Ractors (Cartridge::Game#shareable_if_possible). The proc
      # this makes is cut loose in its place, so everything it needs later is written into it.
      #
      # +checked+ false leaves the checks out, for a block that has good reason to reach further
      # than a game does: a test's, which names its own helpers.
      def rewrite(block, allow: [], checked: true)
        file, line = block.source_location
        rewriter = Rewriter.new(*source_and_block_of(block), outer_locals: block.binding.local_variables)
        code = callable_source(rewriter, block)
        source = checked ? checked_source(rewriter, code, file, allow) : code
        eval(source, block.binding, file, line) # rubocop:disable Security/Eval
      end

      # What a game runs for +block+: the block rewritten, or as it is if it cannot be, as with one
      # made from a method, or one this module made already.
      def game_block(block, allow: []) = rewritable?(block) ? rewrite(block, allow: allow) : block

      # A lambda stays one, since it checks what it is given and a proc does not. `->` has its
      # arrow in its own text, and `lambda { }` does not.
      def callable_source(rewriter, block)
        return rewriter.rewritten_block if rewriter.block_node.is_a?(Prism::LambdaNode)

        "#{block.lambda? ? 'lambda' : 'proc'} #{rewriter.rewritten_block}"
      end

      def checked_source(rewriter, code, file, allow)
        checks = BlockChecks.new(rewriter.block_node, file: file, allow: allow)
        checks.refuse_outside_calls!
        checks.refuse_game_code_in_plain_files!
        "proc { |*__plain_ruby_given| #{checks.constant_check}; (#{code}).call(*__plain_ruby_given) }"
      end

      # Can +block+ be rewritten? It takes a file to read and a scope to run in, and a proc this
      # module made already has no file of its own, which is how it is not rewritten twice.
      def rewritable?(block)
        iseq = RubyVM::InstructionSequence.of(block)
        return false unless iseq&.absolute_path && File.file?(iseq.absolute_path)

        block.binding
        true
      rescue ArgumentError
        false
      end

      # What the block's source is rewritten into, for reading and for a test.
      def rewritten_source(block) = Rewriter.new(*source_and_block_of(block)).rewritten_block

      # The block's file and its node. A file is read and parsed once, per Ractor since a tree is
      # not shared.
      def source_and_block_of(block)
        path, line = block.source_location
        source, blocks = parsed_file(path)
        starting = blocks.fetch(line, [])
        found = starting.one? ? starting.first : node_at_column(starting, block)
        unless found.is_a?(Prism::BlockNode) || found.is_a?(Prism::LambdaNode)
          raise ArgumentError, "No block starts at line #{line}, so this game cannot be read."
        end

        [source, found]
      end

      # The last that starts by that column, since Ruby counts a `->` from its body, not its arrow.
      def node_at_column(nodes, block)
        column = block_start_column(block)
        nodes.select { |node| node.location.start_column <= column }.max_by { |node| node.location.start_column }
      end

      # Which column +block+ starts at, which only matters when two start on one line. Ruby can
      # say, but asking from several Ractors at once crashes or hangs it, since they share the
      # block's code. A held file lock is the only lock Ractors can share.
      def block_start_column(block)
        File.open(__FILE__) do |file|
          file.flock(File::LOCK_EX)
          RubyVM::InstructionSequence.of(block).to_a[4][:code_location][1]
        end
      end

      def parsed_file(path)
        files = (Ractor.current[:plain_ruby_parsed_files] ||= {})
        files[path] ||= begin
          source = File.binread(path)
          [source, code_by_line(Prism.parse(source).value, Hash.new { |all, line| all[line] = [] })]
        end
      end

      # Methods are listed too, since a proc made from one is not a block to rewrite, and must not
      # be taken for a block beside it on the line.
      def code_by_line(node, found)
        case node
        when Prism::BlockNode, Prism::LambdaNode, Prism::DefNode then found[node.location.start_line] << node
        end
        node.compact_child_nodes.each { |child| code_by_line(child, found) }
        found
      end

      # A whole file of a game in normal Ruby, the file a game splits a part into, as source.
      def rewritten_file(path)
        source = File.binread(path)
        root = Prism.parse(source).value
        # What stands before the first line of code stays: the magic comment that freezes the
        # file's strings is there, and so is every line the numbers after it count from.
        opening = source.byteslice(0, root.location.start_offset).force_encoding(Encoding::UTF_8)
        "#{opening}#{Rewriter.new(source).rewritten(root)}"
      end

      # The block's source with its constructs written out as calls. It builds new text rather
      # than editing in place, since a trailing `if` is evaluated before what stands to its left.
      class Rewriter
        STEPS = "::VBlank::DSL::PlainRubySteps"

        attr_reader :block_node

        # +outer_locals+ are the names the block's scope holds. Written further down the method a
        # block sits in, one is no local to the block as Ruby first read it, and yet it is to
        # `eval`: `screen :tiled` would stop being a call. Those calls are written with `self.`.
        def initialize(source, block_node = nil, outer_locals: [])
          @source = source
          @block_node = block_node
          @outer_locals = outer_locals
          @answers = 0
          @open_tests = []
        end

        def rewritten_block = rewritten(@block_node)

        def rewritten(node)
          @names = LocalNames.new(node)
          text(node)
        end

        private

        def between(from, upto) = @source.byteslice(from...upto).force_encoding(Encoding::UTF_8)

        # Only the line ends between two places, so what follows keeps its line number.
        def line_ends_between(from, upto) = "\n" * between(from, upto).count("\n")

        def text(node)
          case node
          when Prism::IfNode, Prism::UnlessNode then conditional_text(node)
          when Prism::WhileNode then loop_text(node, "loop_while")
          when Prism::UntilNode then loop_text(node, "loop_until")
          when Prism::AndNode then joined_text(node, "both")
          when Prism::OrNode then joined_text(node, "either")
          when Prism::CallNode then call_text(node)
          when Prism::LocalVariableWriteNode then guarded_write_text(node, write_text(node))
          when Prism::LocalVariableOperatorWriteNode then guarded_write_text(node, change_text(node))
          when Prism::InstanceVariableWriteNode then instance_variable_write_text(node)
          when Prism::InstanceVariableOperatorWriteNode then change_text(node)
          when Prism::IndexOperatorWriteNode then place_change_text(node, index_text(node))
          when Prism::CallOperatorWriteNode then place_change_text(node, "#{text(node.receiver)}.#{node.read_name}")
          when Prism::ReturnNode, Prism::BreakNode, Prism::NextNode then jump_text(node)
          when Prism::BlockNode, Prism::LambdaNode, Prism::DefNode then own_scope_text(node)
          else copied_text(node)
          end
        end

        # The node's text, with what is inside it rewritten. A heredoc's lines sit past the end
        # of the node that opened them, and the text around the node carries them, so they
        # are left out here.
        def copied_text(node)
          at = node.location.start_offset
          ends = node.location.end_offset
          pieces = node.compact_child_nodes.sort_by { |child| child.location.start_offset }.map do |child|
            start = child.location.start_offset
            next "" if start < at || start >= ends

            piece = between(at, start) + text(child)
            at = child.location.end_offset
            piece
          end
          pieces.join + between(at, node.location.end_offset)
        end

        # A `return` in a block belongs to that block, so tests open outside it do not apply.
        def own_scope_text(node)
          outer = @open_tests
          @open_tests = []
          copied_text(node)
        ensure
          @open_tests = outer
        end

        def under_open_test(test)
          @open_tests += [test]
          yield
        ensure
          @open_tests = @open_tests[0...-1]
        end

        # Plain Ruby jumps as it always has. Under a test the game makes, the step refuses it.
        # The `if true` is for Ruby's parser, which will not let a jump stand as a value.
        def jump_text(node)
          return copied_text(node) if @open_tests.empty?

          word = node.is_a?(Prism::ReturnNode) ? "return" : node.is_a?(Prism::BreakNode) ? "break" : "next"
          refusals = @open_tests.map { |test| "#{test}.refuse_jump!(:#{word})" }.join("; ")
          "(#{refusals}; if true then #{copied_text(node)} end)"
        end

        def call_text(node)
          return "#{STEPS}.opposite(#{argument(node.receiver)})" if node.name == :! && node.receiver
          return index_write_text(node) if node.name == :[]= && node.receiver
          return attribute_write_text(node) if node.attribute_write? && node.receiver
          return "self.#{copied_text(node)}" if node.receiver.nil? && @outer_locals.include?(node.name)

          copied_text(node)
        end

        def index_write_text(node)
          arguments = node.arguments.arguments.map { |each_argument| argument(each_argument) }.join(", ")
          "#{STEPS}.assign_index(#{argument(node.receiver)}, #{arguments})"
        end

        def attribute_write_text(node)
          name = node.name.to_s.delete_suffix("=")
          value = argument(node.arguments.arguments.first)
          "#{STEPS}.assign_attribute(#{argument(node.receiver)}, :#{name}, #{value})"
        end

        def index_text(node) = "#{text(node.receiver)}[#{node.arguments ? text(node.arguments) : ''}]"

        # `+=` on a place. The block is what Ruby would do, for a place that holds no variable.
        def place_change_text(node, place)
          "#{STEPS}.change_place(#{place}, :#{node.binary_operator}, #{argument(node.value)}) " \
            "{ |__plain_ruby_changed| #{place} = __plain_ruby_changed }"
        end

        # A plain number changed from inside a block no one can place: `each` may be Ruby's, which
        # runs now, or a pool's, which records game code. Only running it can tell, so the step
        # looks, using the question the block's builder answers.
        def guarded_write_text(node, written)
          return written unless @names.plain_number_changed_from_block?(node)

          recording = "(respond_to?(:recording_game_code?) && recording_game_code?)"
          "(#{STEPS}.refuse_lost_number!(:#{node.name}, #{recording}); #{written})"
        end

        # A part of a game keeps its variables in these, so one holding a game variable is changed.
        def instance_variable_write_text(node)
          prefix = between(node.location.start_offset, node.value.location.start_offset)
          "#{prefix}#{STEPS}.assign(#{node.name}, (#{value_text(node.value)}))"
        end

        def write_text(node)
          prefix =between(node.location.start_offset, node.value.location.start_offset)
          case @names.action_for(node)
          when :declare then "#{prefix}#{declaration(node)}"
          when :start then "#{prefix}#{STEPS}.start(#{declaration(node)}, #{text(node.value)})"
          when :assign then "#{prefix}#{STEPS}.assign(#{node.name}, (#{value_text(node.value)}))"
          when :reassign then "#{prefix}#{STEPS}.reassign(#{node.name}, (#{value_text(node.value)}))"
          else "#{prefix}#{kept_value_text(node.value)}"
          end
        end

        def declaration(node) = "var(:#{@names.variable_name_of(node)}, #{text(node.value)})"

        def kept_value_text(value)
          return value_text(value) unless value.is_a?(Prism::LocalVariableReadNode) && @names.variable_read?(value)

          "#{STEPS}.copy(#{text(value)})"
        end

        def value_text(value)
          conditional = value.is_a?(Prism::IfNode) || value.is_a?(Prism::UnlessNode)
          conditional ? conditional_text(value, kept: true) : text(value)
        end

        def change_text(node)
          "#{node.name} = #{STEPS}.change(#{node.name}, :#{node.binary_operator}, #{argument(node.value)})"
        end

        # The right side is a block so plain values keep Ruby's skipping of it.
        def joined_text(node, step) = "#{STEPS}.#{step}(#{argument(node.left)}) { #{text(node.right)} }"

        # A value handed to a step. The parentheses are for a call written without its own, like
        # `actions = menu :actions do ... end`, which Ruby takes alone but not as an argument.
        def argument(node) = "(#{text(node)})"

        # A real `while`: a plain test goes round as usual, and a game test's body runs once,
        # recording itself into a loop the game makes.
        def loop_text(node, step)
          test = "__plain_ruby_#{@answers += 1}"
          statements = node.statements
          trailing = statements && statements.location.start_offset < node.predicate.location.start_offset
          opened = node.predicate.location.end_offset
          shut_at = node.closing_loc&.start_offset || node.location.end_offset
          body = under_open_test(test) do
            if trailing then text(statements)
            elsif statements then side_text(opened, statements, shut_at)
            else line_ends_between(opened, shut_at)
            end
          end
          "(#{test} = #{STEPS}.#{step} { #{text(node.predicate)} }; while #{test}.again?; #{body}; end)"
        end

        # A conditional as two real `if`s, one for each side. A plain test takes one; a game
        # test takes both, once each. +kept+ is for one whose value is used, by `x = ...`.
        def conditional_text(node, kept: false)
          answer = "__plain_ruby_#{@answers += 1}"
          shut_at = node.end_keyword_loc&.start_offset || node.location.end_offset
          sides = under_open_test(answer) do
            "#{yes_side_text(node, answer, shut_at, kept)}#{no_side_text(node, answer, shut_at, kept)}"
          end
          "(#{answer} = #{STEPS}.test(#{test_text(node)}); #{sides}#{answer}.#{kept ? 'kept' : 'answer'})"
        end

        def test_text(node)
          test = predicate_text(node.predicate)
          node.is_a?(Prism::UnlessNode) ? "#{STEPS}.opposite(#{test})" : test
        end

        # What is handed in or kept in an object is truthy as in Ruby. See PlainRubySteps.truthy.
        def predicate_text(predicate)
          handed_in = predicate.is_a?(Prism::LocalVariableReadNode) && @names.parameter_read?(predicate)
          handed_in || field_read?(predicate) ? "#{STEPS}.truthy(#{argument(predicate)})" : argument(predicate)
        end

        def field_read?(node)
          node.is_a?(Prism::CallNode) && node.receiver && node.arguments.nil? && node.block.nil? &&
            node.name.to_s.match?(/\A[a-z_]\w*\z/)
        end

        def other_side(node) = node.is_a?(Prism::UnlessNode) ? node.else_clause : node.subsequent

        def side_step(kept) = kept ? "keep" : "finish"

        def yes_side_text(node, answer, shut_at, kept)
          statements = node.statements
          trailing = statements && statements.location.start_offset < node.predicate.location.start_offset
          ends = other_side(node)&.location&.start_offset || shut_at
          opened = node.predicate.location.end_offset
          body = if trailing then text(statements)
                 elsif statements then side_text(opened, statements, ends)
                 else line_ends_between(opened, ends)
                 end
          "if #{answer}.run_yes_side?; #{answer}.#{side_step(kept)}((#{body})); end; "
        end

        def no_side_text(node, answer, shut_at, kept)
          other = other_side(node)
          return "" unless other

          body = if other.is_a?(Prism::ElseNode)
                   opened = other.else_keyword_loc.end_offset
                   statements = other.statements
                   statements ? side_text(opened, statements, shut_at) : line_ends_between(opened, shut_at)
                 else
                   "#{conditional_text(other, kept: kept)}#{line_ends_between(other.location.end_offset, shut_at)}"
                 end
          "if #{answer}.run_no_side?; #{answer}.#{side_step(kept)}((#{body})); end; "
        end

        # One side's statements. What follows them is kept as written, because a heredoc's
        # lines sit there, past the end of the statement that opened it.
        def side_text(opened, statements, ends)
          "#{line_ends_between(opened, statements.location.start_offset)}#{text(statements)}" \
            "#{between(statements.location.end_offset, ends)}"
        end
      end
    end
  end
end
