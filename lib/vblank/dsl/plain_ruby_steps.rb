# frozen_string_literal: true

module VBlank
  module DSL
    # What a rewritten game block calls as it runs (see PlainRuby). Each step looks at the value
    # it is handed: a test the game makes as it plays records game code, and anything else does
    # just what Ruby would.
    module PlainRubySteps
      MOST_PASSES = IR::Guardrails::Checks::LoopNeverWaits::MOST_PASSES

      # What `+=` and its relatives are on a game variable, where one exists. Any other
      # operator is the variable set to the sum.
      CHANGING_VERBS = { :+ => :add!, :- => :sub! }.freeze

      COMPARISONS = %i[< > <= >= == !=].freeze

      module_function

      # Truthiness is Ruby's. Only a test, or a yes or no the game keeps, has an answer that waits
      # for the game to play. Every other value is answered here: nil and false are falsy, and
      # everything else is truthy, a number of the game's among them, whatever it holds.
      def game_test?(value) = value.is_a?(Condition) || (value.is_a?(Value) && value.yes_no?)

      # Does this name a place that keeps a number, rather than a working-out of one?
      def variable?(value) = value.is_a?(Value) && value.handle?

      # Can a game variable start with this?
      def game_value?(value) = [Integer, Float, Symbol, TrueClass, FalseClass].any? { |kind| value.is_a?(kind) }

      def as_condition(value) = value.is_a?(Value) ? value != 0 : value

      # A conditional's test, as an object the rewritten `if` asks which sides to run. A number
      # worked out for it is truthy and used for nothing more, so no check counts it as dropped.
      def test(value)
        return GameTest.new(as_condition(value)) if game_test?(value)

        value.discard if value.is_a?(Value)
        BuildTest.new(value)
      end

      # The other answer to a test, for `!` and `unless`.
      def opposite(value)
        return !value unless value.is_a?(Value) && value.yes_no?

        value == 0
      end

      # `&&`. Ruby skips the right side once the left has decided. A game test cannot: both
      # sides are worked out as the game plays, whichever way the left turns out.
      def both(left)
        return left && yield unless game_test?(left)

        condition = as_condition(left)
        right = yield
        refuse_list_read!(condition, right, "&&")
        return condition & as_condition(right) if game_test?(right)

        right ? condition : condition.discard
      end

      # `||`, the same way round.
      def either(left)
        return left || yield unless game_test?(left)

        condition = as_condition(left)
        right = yield
        refuse_list_read!(condition, right, "||")
        return condition | as_condition(right) if game_test?(right)

        right ? condition.discard || right : condition
      end

      def loop_while(&test) = LoopTest.new(test, stops_when: false)
      def loop_until(&test) = LoopTest.new(test, stops_when: true)

      # Put +value+ in a game variable. A yes or no is kept as 1 or 0, and a test's answer is
      # worked out as the game plays.
      def store(target, value)
        case value
        when true then target.set!(1)
        when false then target.set!(0)
        when Condition then store_answer(target, value)
        else target.set!(value)
        end
      end

      def store_answer(target, condition)
        answer = GameTest.new(condition)
        answer.run_yes_side?
        target.set!(1)
        answer.finish(nil)
        answer.run_no_side?
        target.set!(0)
        answer.finish(nil)
      end

      # `x = value` where x is a game variable.
      def assign(target, value)
        return value unless variable?(target)

        store(target, value)
        target
      end

      # `x = value` where x was not made by `var` but may hold a game variable anyway: a method's
      # argument, or `x = m[:x]`. Given another variable, the name moves to it. Given a number, the
      # game's variable takes it, as the same line does on a name made by `var`.
      def reassign(target, value)
        return value if !variable?(target) || variable?(value)

        store(target, value)
        target
      end

      # `x += amount`, and every operator like it.
      def change(target, operator, amount)
        return target.public_send(operator, amount) unless variable?(target)

        verb = CHANGING_VERBS[operator]
        verb ? target.public_send(verb, amount) : target.set!(target.public_send(operator, amount))
        target
      end

      # `hash[:x] += amount` and `hero.x += amount`.
      def change_place(current, operator, amount)
        return change(current, operator, amount) if variable?(current)

        yield current.public_send(operator, amount)
      end

      # `collection[key] = value`. A game variable kept in a Hash or an Array is changed where
      # it stands: putting a new number in its slot would leave the game's variable as it was.
      # A game's own list answers `[]=` itself. A Hash is asked with `fetch`, since `[]` runs its
      # default block for a key it does not hold, and that block may be this very write.
      def assign_index(collection, *keys, value)
        current = collection.fetch(keys.first, nil) if collection.is_a?(Hash)
        current = collection[*keys] if collection.is_a?(Array)
        refuse_new_slot!(collection, keys.first, value) if current.nil?
        return collection[*keys] = value unless variable?(current)

        store(current, value)
      end

      # A number given to a key that a Hash of game variables does not hold is a misspelt key: it
      # would go in as a plain Ruby number, and the game's variable would stay as it was.
      def refuse_new_slot!(collection, key, value)
        return unless collection.is_a?(Hash) && !collection.empty? && game_value?(value) && !value.is_a?(Symbol)
        return unless collection.each_value.all? { |each_value| variable?(each_value) }

        refuse!("This Hash holds game variables and has no key #{key.inspect}, so the game would never " \
                "see this number. The keys are #{collection.keys.map(&:inspect).join(', ')}. To fix " \
                "this, use one of those keys.")
      end

      # `hero.x = value`.
      def assign_attribute(receiver, name, value)
        current = receiver.public_send(name) if receiver.respond_to?(name)
        return receiver.public_send(:"#{name}=", value) unless variable?(current)

        store(current, value)
      end

      # A plain number changed by code the game runs would change once, while building, and the
      # game would never see it. See Rewriter#guarded_write_text.
      def refuse_lost_number!(name, recording_game_code)
        return unless recording_game_code

        refuse!("`#{name}` is a plain number, and this line runs as the game plays, so the game " \
                "will never see the change. To fix this, start it with `#{name} = var :#{name}, 0`.")
      end

      # The line that makes a variable in game code runs on every pass, as a Ruby line would.
      def start(variable, value)
        return value unless variable?(variable)

        store(variable, value)
        variable
      end

      # `old = hp`. While the game plays that must keep hp's number as it is now, where a plain
      # second name would follow hp when it changes.
      def copy(value) = variable?(value) ? value.kept_copy : value

      def refuse!(message)
        raise PlainRuby::Refused, "#{message}#{Messages::AuthorSource.at_author_line}"
      end

      # `i < size && things[i] == 1` looks guarded by the left, as it is in Ruby. The game works
      # out both sides, so an index the left ruled out still stops the game. It takes both
      # halves: the left comparing a variable, and the right using that variable as an index.
      def refuse_list_read!(left, right, word)
        return unless game_test?(right)
        return if (compared_variables(left.node) & list_index_variables(right.node)).empty?

        refuse!("The right side of `#{word}` reads a list, and a game works out both sides every " \
                "time. An index the left side rules out still stops the game. To fix this, put one " \
                "`if` inside another.")
      end

      def compared_variables(node)
        comparisons = node.walk.select { |each_node| each_node.kind == :binop && COMPARISONS.include?(each_node.op) }
        comparisons.flat_map { |comparison| [comparison.lhs, comparison.rhs] }
                   .select { |side| side.kind == :var_ref }.map(&:name)
      end

      def list_index_variables(node)
        reads = node.walk.select { |each_node| each_node.kind == :list_get }
        reads.flat_map { |read| read.index.walk.select { |each_node| each_node.kind == :var_ref }.map(&:name) }
      end

      # A test made while building: one side runs, as in plain Ruby, and its value is the answer.
      class BuildTest
        attr_reader :answer

        alias kept answer

        def initialize(value)
          @value = value
        end

        def run_yes_side? = !!@value
        def run_no_side? = !@value
        def finish(value) = @answer = value
        def keep(value) = @answer = value
        def refuse_jump!(_word) = nil
      end

      # A test the game makes as it plays. BOTH sides run, once each, to record their code into
      # the two arms of one branch.
      class GameTest
        def initialize(condition)
          @condition = condition
        end

        def run_yes_side?
          @if_node = @condition.open_branch
          true
        end

        def run_no_side?
          @other_side = true
          @condition.open_other_branch(@if_node)
          true
        end

        def finish(_value) = @condition.close_branch
        def answer = nil

        # A side's value, for `x = test ? a : b`. There is no way to pick one of two numbers in
        # the game, so each side stores its number in one hidden variable.
        def keep(value)
          yes_no = [true, false].include?(value) || value.is_a?(Condition)
          unless yes_no || value.is_a?(Integer) || value.is_a?(Value)
            PlainRubySteps.refuse!("A test made as the game plays can only choose between numbers, " \
                                   "or between `true` and `false`. This side is #{value.inspect}. A " \
                                   "game variable cannot hold that.")
          end
          @kept ||= @condition.hidden_variable
          @kept.yes_no! if yes_no || (value.is_a?(Value) && value.yes_no?)
          PlainRubySteps.store(@kept, value)
          @condition.close_branch
        end

        def kept
          return @kept if @other_side

          PlainRubySteps.refuse!("`x = if ...` needs an `else`. Without one, x has no number when " \
                                 "the test fails, and a game has no nil. To fix this, add an `else`.")
        end

        def refuse_jump!(word) = PlainRubySteps.refuse_jump!(word)
      end

      def refuse_jump!(word)
        refuse!("`#{word}` cannot leave code the game runs as it plays. This block only records " \
                "what the game will do, so there is nothing to #{word} from yet. To fix this, " \
                "put the test in the `if` or `while` around this code.")
      end

      # A `while` or `until`, whose test is asked again each time round. On a plain value that
      # is all it is. On a game test the body runs ONCE, recording itself into a loop in the
      # game, and the second asking closes that loop.
      class LoopTest
        def initialize(test, stops_when:)
          @test = test
          @stops_when = stops_when
        end

        def again?
          return close_game_loop if @game_loop

          value = @test.call
          return @stops_when ? !value : !!value unless PlainRubySteps.game_test?(value)

          open_game_loop(value)
        end

        def refuse_jump!(word)
          PlainRubySteps.refuse_jump!(word) if @game_loop
        end

        private

        def open_game_loop(value)
          held = PlainRubySteps.as_condition(value)
          @game_loop = @stops_when ? held : !held
          @game_loop.open_repeat(MOST_PASSES)
          true
        end

        def close_game_loop
          @game_loop.close_repeat
          false
        end
      end
    end
  end
end
