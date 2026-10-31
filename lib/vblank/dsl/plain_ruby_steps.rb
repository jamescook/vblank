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

      # Bits on numbers, and on tests a join with both sides worked out.
      BIT_JOINS = %i[& | ^].freeze

      module_function

      # Truthiness is Ruby's. Only a test, or a yes or no the game keeps, has an answer that waits
      # for the game to play. Every other value is answered here: nil and false are falsy, and
      # everything else is truthy, a number of the game's among them, whatever it holds.
      def game_test?(value) = value.is_a?(Condition) || (value.is_a?(Value) && (value.boolean? || !value.truth.nil?))

      # Does this name a place that keeps a number, rather than a working-out of one?
      def variable?(value) = value.is_a?(Value) && value.handle?

      # Can a game variable start with this?
      def game_value?(value) = [Integer, Float, Symbol, TrueClass, FalseClass].any? { |kind| value.is_a?(kind) }

      def as_condition(value)
        return value unless value.is_a?(Value)

        value.truth ? value.truth == Value::TRUTHY_HELD : value != 0
      end

      # `x.nil?`. A name that keeps what it holds is asked as the game plays.
      def nil_test(value) = value.is_a?(Value) && value.truth ? value.truth == Value::NIL_HELD : value.nil?

      # A conditional's test, as an object the rewritten `if` asks which sides to run. A number
      # worked out for it is truthy and used for nothing more, so no check counts it as dropped.
      def branch_test(value)
        return GameTest.new(as_condition(value)) if game_test?(value)

        value.discard if value.is_a?(Value)
        BuildTest.new(value)
      end

      # The other answer to a test, for `!` and `unless`.
      def opposite(value)
        return !value unless value.is_a?(Value) && game_test?(value)

        value.truth ? value.truth != Value::TRUTHY_HELD : value == 0
      end

      # `&&`. Two tests that only compare numbers join into one, both worked out as the game
      # plays, which nobody can tell from Ruby's skipping of the right side. A right side that
      # does something, or reads a list, is really skipped (see #side_under). +used+ is false
      # for a join standing alone as a statement, whose answer nothing reads.
      def join_both(left, used: true, into: nil)
        return left && yield unless game_test?(left)

        condition = as_condition(left)
        right, if_node = side_under(condition) { yield }
        return keep_side_answer(condition, if_node, right, otherwise: 0, used: used, into: into) if if_node
        return condition & as_condition(right) if game_test?(right)

        right ? condition : condition.discard
      end

      # `||`, the same way round.
      def join_either(left, used: true, into: nil)
        return left || yield unless game_test?(left)
        return number_or_other_side(left) { yield } if left.is_a?(Value) && left.truth

        condition = as_condition(left)
        unless_left = !condition
        right, if_node = side_under(unless_left) { yield }
        return keep_side_answer(unless_left, if_node, right, otherwise: 1, used: used, into: into) if if_node
        return condition | as_condition(right) if game_test?(right)

        right ? condition.discard || right : condition
      end

      # One `when`: does +subject+ match any of +choices+? A plain subject is Ruby's to answer. A
      # number the game keeps becomes a test, one choice at a time.
      def when_test(subject, *choices)
        return choices.any? { |choice| choice === subject } unless subject.is_a?(Value) || subject.is_a?(Condition) # rubocop:disable Style/CaseEquality

        refuse_game_code!("`case` cannot ask about a test the game makes. To fix this, write `if`.") if subject.is_a?(Condition)

        choices.map { |choice| test_of_choice(subject, choice) }.reduce(:|)
      end

      def test_of_choice(subject, choice)
        case choice
        when Integer, Symbol, Value then subject == choice
        when true then subject == 1
        when false then subject == 0
        when Range then test_of_range(subject, choice)
        else refuse_game_code!("`when #{choice.inspect}` cannot be asked of a number the game keeps. A game " \
                               "can compare a number, a symbol, a range or a variable.")
        end
      end

      def test_of_range(subject, range)
        below_top = range.exclude_end? ? subject < range.end : subject <= range.end
        (subject >= range.begin) & below_top
      end

      # `target || 7` on a name that may hold nil: its number if it is truthy, and the right side
      # if not, picked the way `x = test ? a : b` picks.
      def number_or_other_side(left)
        test = GameTest.new(as_condition(left))
        test.open_yes_side
        test.keep_side_value(number_of(left))
        test.open_no_side
        test.keep_side_value(yield)
        test.picked_value
      end

      # The number alone, which no longer counts as a test.
      def number_of(value) = value + 0

      # The left side of `found or next`, as Ruby would answer it. A test the game makes has no
      # answer yet, and a jump needs one now.
      def answer_before_jump(value, word)
        refuse_jump!(word) if game_test?(value)

        !!value
      end

      # The right side of `&&` or `||`, worked out under +condition+, and the branch it is in when
      # that branch must stay, still open: the side did something the game does, a sound or a
      # change, or reads a list at a place the left may have ruled out. If it only made a test,
      # nothing is left of the branch and the two tests join.
      def side_under(condition)
        if_node = condition.open_branch
        right = yield
        return [right, if_node] unless if_node.children.empty? && !reads_list?(right)

        condition.close_branch
        condition.take_back_branch(if_node)
        [right, nil]
      end

      # A slot at a place worked out as the game plays. One past the end stops the game. A pool
      # keeps its fields in lists too, read at a row that `each` handed over, always a real one.
      def reads_list?(value)
        return false unless value.is_a?(Condition) || value.is_a?(Value)

        value.node.walk.any? do |node|
          next false unless node.kind == :list_get && Messages::MadeNames.read(node.name)&.first != :pool_field

          node.index.walk.any? { |each_node| each_node.kind == :var_ref }
        end
      end

      # Closes the branch #side_under left open. The join's answer is the right side's on that
      # side and +otherwise+ on the other, so it is kept: in +into+, the game variable it is going
      # to anyway, or else in a hidden variable.
      def keep_side_answer(condition, if_node, right, otherwise:, used:, into: nil)
        unless used
          forget_value(right)
          condition.close_branch
          return
        end

        answer = into || condition.hidden_variable(:join)
        answer.mark_boolean! unless into
        store_truthiness(answer, right)
        condition.close_branch
        condition.open_other_branch(if_node)
        answer.set!(otherwise)
        condition.close_branch
        answer
      end

      # A test's answer goes in as the game plays. Anything else counts by Ruby's truthiness.
      def store_truthiness(target, value)
        return store_in_variable(target, as_condition(value)) if game_test?(value)

        forget_value(value)
        target.set!(value ? 1 : 0)
      end

      def forget_value(value)
        value.discard if value.is_a?(Value) || value.is_a?(Condition)
      end

      # `a & b`, `a | b` and `a ^ b`: bits on numbers, and Ruby's own on anything else. Between
      # tests they join, working out both sides as Ruby does for these on true and false.
      def bits(left, operator, right)
        if game_test?(left) && game_test?(right)
          as_condition(left).public_send(operator, as_condition(right))
        elsif game_test?(left) then bits_beside_plain(as_condition(left), operator, right)
        elsif game_test?(right) && (left.nil? || left == true || left == false)
          bits_beside_plain(as_condition(right), operator, left)
        else left.public_send(operator, right)
        end
      end

      # A test beside a plain value, which counts by its truthiness and decides now.
      def bits_beside_plain(test, operator, plain)
        case operator
        when :& then plain ? test : test.discard
        when :| then plain ? !test.discard : test
        else plain ? !test : test
        end
      end

      def loop_while(&test) = LoopTest.new(test, stops_when: false)
      def loop_until(&test) = LoopTest.new(test, stops_when: true)

      # Put +value+ in a game variable. A yes or no is kept as 1 or 0, and a test's answer is
      # worked out as the game plays.
      def store_in_variable(target, value)
        return store_with_truth(target, value) if target.truth

        case value
        when true then target.set!(1)
        when false, nil then target.set!(0)
        when Condition then store_answer(target, value)
        else
          refuse_number_in_boolean!(target) if target.boolean? && value.is_a?(Value) && !value.boolean?
          target.set!(value)
        end
      end

      # The same, on a name that keeps what it holds (see Value#truth).
      def store_with_truth(target, value)
        case value
        when nil then target.truth.set!(Value::NIL_HELD)
        when false then target.truth.set!(Value::FALSE_HELD)
        when true then store_truthy(target, 1)
        when Condition then store_truth_of_test(target, value)
        when Value then store_value_with_truth(target, value)
        else store_truthy(target, value)
        end
      end

      def store_truthy(target, number)
        target.set!(number)
        target.truth.set!(Value::TRUTHY_HELD)
      end

      def store_truth_of_test(target, condition)
        answer = GameTest.new(condition)
        answer.open_yes_side
        store_truthy(target, 1)
        answer.close_side(nil)
        answer.open_no_side
        store_with_truth(target, false)
        answer.close_side(nil)
      end

      def store_value_with_truth(target, value)
        return store_truthy(target, value) unless value.truth

        target.set!(value)
        target.truth.set!(value.truth)
      end

      # The first line of a name that can hold nil or false as well as a number.
      def start_with_truth(value)
        own = yield(0)
        return own.tap(&:start_truth_as_nil!) if value.nil?

        own.keep_truth!
        store_with_truth(own, value)
        own
      end

      def store_answer(target, condition)
        answer = GameTest.new(condition)
        answer.open_yes_side
        target.set!(1)
        answer.close_side(nil)
        answer.open_no_side
        target.set!(0)
        answer.close_side(nil)
      end

      # A plain name is about to be changed under +test+. A test the game makes runs both sides
      # while building, so a plain name would end up with the last side's value whichever way
      # the game goes. It gets a hidden variable holding its value now, and the sides change that.
      # Tests already open around this one have seen to it, in +outer+.
      def promote(value, test, *outer, may_stay_nil: false)
        return value unless test.game? && outer.none?(&:game?)
        return value unless value.nil? || game_value?(value) || value.is_a?(Value) || value.is_a?(Condition)

        own = test.hidden_variable(:promoted, like: value.is_a?(Value) ? value : nil)
        own.mark_boolean! if [true, false].include?(value) || value.is_a?(Condition) || (value.is_a?(Value) && value.boolean?)
        own.unwritten = value.nil?
        own.start_truth_as_nil! if may_stay_nil && value.nil?
        store_in_variable(own, value) unless value.nil?
        own
      end

      # `x = value` on a name #promote saw to, if one of +tests+ is the game's. A name not given
      # anything yet can take an object made here, as `actions = menu ...` does, since a verb
      # that declares something runs once however the test goes.
      def write_under(tests, name, target, value)
        return value unless tests.any?(&:game?)

        refuse_object_under_test!(name, target) unless variable?(target)
        return assign(target, value) if game_value?(value) || value.is_a?(Value) || value.is_a?(Condition)

        refuse_object_under_test!(name, value) unless target.unwritten
        target.forget_truth!
        value
      end

      # `x = value` under open tests, where x may turn out to hold an object.
      def assign_under(tests, name, target, value)
        refuse_object_under_test!(name, target) if tests.any?(&:game?) && !target.nil? && !number_kept?(target)

        assign(target, value)
      end

      # `x += amount` on such a name.
      def change_under(tests, target, operator, amount)
        tests.any?(&:game?) ? change(target, operator, amount) : target.public_send(operator, amount)
      end

      # The left of a join whose right side changes a name, asked like an `if`'s test.
      class JoinSide
        attr_reader :value

        def initialize(value) = @value = value

        def game? = PlainRubySteps.game_test?(@value)
        def hidden_variable(why, like: nil) = PlainRubySteps.as_condition(@value).hidden_variable(why, like: like)
        def refuse_jump!(word) = PlainRubySteps.refuse_jump!(word)
      end

      def side_of_join(value) = JoinSide.new(value)

      def refuse_change_in_block!(name, tests)
        return unless tests.any?(&:game?)

        refuse_game_code!("`#{name}` is changed inside a block, under a test the game makes as it plays. The " \
                          "block runs while building, so the game cannot follow this. To fix this, start it " \
                          "with `#{name} = var :#{name}, 0`.")
      end

      def refuse_begin_while!(name)
        refuse_game_code!("This `begin` loop changes `#{name}`, and its test is one the game makes as it plays. " \
                          "To fix this, start it with `#{name} = var :#{name}, 0`.")
      end

      def refuse_number_in_boolean!(target)
        refuse_game_code!("`#{target.name}` started as `true` or `false`, and this line gives it a number. A " \
                          "game variable keeps one kind unless the line says so. To fix this, compare the " \
                          "number, like `#{target.name} = count > 0`, or start it with a number.")
      end

      def refuse_object_under_test!(name, held)
        shown = held.is_a?(String) ? held.inspect : "a #{held.class.name.split('::').last}"
        refuse_game_code!("`#{name}` holds #{shown}, and this line changes it under a test the game makes " \
                          "as it plays. A game can keep only numbers, symbols, `true` and `false`. To fix this, " \
                          "keep a number and pick with it.")
      end

      # A variable the author never wrote `var` for, which the out-of-memory error names.
      def made_with_no_var_line(variable)
        variable.note_made_with_no_var_line
        variable
      end

      def number_kept?(value) = value.nil? || game_value?(value) || value.is_a?(Value) || value.is_a?(Condition)

      # `x = value` where x is a game variable. On a name started as nil, something made while
      # building is held as Ruby holds it, and the name keeps no number.
      def assign(target, value)
        return value unless variable?(target)
        return target if value.equal?(target)
        return value.tap { target.forget_truth! } if target.truth && !number_kept?(value)

        store_in_variable(target, value)
        target
      end

      # The first line of a name the game changes later. A number starts a variable. A variable or
      # a working-out gives it a variable of its own holding that number now, since a Ruby name
      # holds a value and never another name. Anything else stays what it is.
      def start_name(value)
        return yield(value) if game_value?(value)

        case value
        when Condition then assign(yield(false), value)
        when Value then assign(own_variable(value) { |start| yield(start) }, value)
        else value
        end
      end

      def own_variable(value)
        own = yield(value.fraction? ? 0.0 : 0)
        own.mark_boolean! if value.boolean?
        own
      end

      # `@x = var :x, 0`. A part of a game keeps its variables in these, and this one is the name's
      # own, so #reassign can tell it from one the name was only handed.
      def keep_as_own(variable)
        variable.own_to_its_name = true
        variable
      end

      # `@x = value`. Given a number, the game's variable takes it. Given another variable, a
      # variable of the name's own takes its number, and the two then change apart, as two Ruby
      # names would. A variable the name was only handed is left alone, and the name moves.
      def reassign(target, value)
        return value unless variable?(target)
        return value if variable?(value) && !target.own_to_its_name
        return target if value.equal?(target)

        store_in_variable(target, value)
        target
      end

      # `x += amount`, and every operator like it.
      def change(target, operator, amount)
        return target.public_send(operator, amount) unless variable?(target)
        return assign(target, bits(target, operator, amount)) if game_test?(target) && BIT_JOINS.include?(operator)

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

        store_in_variable(current, value)
      end

      # A number given to a key that a Hash of game variables does not hold is a misspelt key: it
      # would go in as a plain Ruby number, and the game's variable would stay as it was.
      def refuse_new_slot!(collection, key, value)
        return unless collection.is_a?(Hash) && !collection.empty? && game_value?(value) && !value.is_a?(Symbol)
        return unless collection.each_value.all? { |each_value| variable?(each_value) }

        refuse_game_code!("This Hash holds game variables and has no key #{key.inspect}, so the game would never " \
                "see this number. The keys are #{collection.keys.map(&:inspect).join(', ')}. To fix " \
                "this, use one of those keys.")
      end

      # `hero.x = value`.
      def assign_attribute(receiver, name, value)
        current = receiver.public_send(name) if receiver.respond_to?(name)
        return receiver.public_send(:"#{name}=", value) unless variable?(current)

        store_in_variable(current, value)
      end

      # A plain number changed by code the game runs would change once, while building, and the
      # game would never see it. See Rewriter#guarded_write_text.
      def refuse_lost_number!(name, recording_game_code)
        return unless recording_game_code

        refuse_game_code!("`#{name}` is a plain number, and this line runs as the game plays, so the game " \
                "will never see the change. To fix this, start it with `#{name} = var :#{name}, 0`.")
      end

      # A right side of `a, b = b, a`, kept before the writes reach what it reads.
      def number_now(value) = value.is_a?(Value) ? value.hidden_copy(:swap) : value

      # What a name was given, kept as it is on this line, since something it was worked out from
      # changes before it is read. A number needs no keeping.
      def kept_answer(value)
        return value.hidden_copy if value.is_a?(Value)
        return value unless value.is_a?(Condition)

        kept = value.hidden_variable(:copy)
        kept.mark_boolean!
        store_answer(kept, value)
        kept
      end

      # `old = hp`. While the game plays that must keep hp's number as it is now, where a plain
      # second name would follow hp when it changes.
      def copy_of_variable(value) = variable?(value) ? value.kept_copy : value

      def refuse_game_code!(message)
        raise PlainRuby::Refused, "#{message}#{Messages::AuthorSource.at_author_line}"
      end

      # A test made while building: one side runs, as in plain Ruby, and its value is the answer.
      class BuildTest
        attr_reader :answer

        alias picked_value answer
        alias tail_value answer

        def initialize(value)
          @value = value
        end

        def game? = false
        def open_yes_side = !!@value
        def open_no_side = !@value
        def close_side(value) = @answer = value
        def keep_side_value(value) = @answer = value
        def keep_tail_value(value) = @answer = value
        def store_side(target, value) = @answer = PlainRubySteps.assign(target, value)
        def refuse_jump!(_word) = nil
      end

      # A test the game makes as it plays. BOTH sides run, once each, to record their code into
      # the two arms of one branch.
      class GameTest
        def initialize(condition)
          @condition = condition
        end

        def game? = true
        def hidden_variable(why, like: nil) = @condition.hidden_variable(why, like: like)

        def open_yes_side
          @if_node = @condition.open_branch
          true
        end

        def open_no_side
          @other_side = true
          @condition.open_other_branch(@if_node)
          true
        end

        def close_side(_value) = @condition.close_branch
        def answer = nil

        # A side's value, for `x = test ? a : b`. There is no way to pick one of two numbers in
        # the game, so each side stores its number in one hidden variable.
        def keep_side_value(value)
          boolean = [true, false].include?(value) || value.is_a?(Condition)
          unless boolean || value.is_a?(Integer) || value.is_a?(Value)
            PlainRubySteps.refuse_game_code!("A test made as the game plays can only choose between numbers, " \
                                   "or between `true` and `false`. This side is #{value.inspect}. A " \
                                   "game variable cannot hold that.")
          end
          @kept ||= @condition.hidden_variable(:picked)
          @kept.mark_boolean! if boolean || (value.is_a?(Value) && value.boolean?)
          PlainRubySteps.store_in_variable(@kept, value)
          @condition.close_branch
        end

        # A ternary ending a method, which may be there for what its sides do. A side a game can
        # keep a value of keeps one. A verb's nil or a handle of its own leaves nothing to answer with.
        def keep_tail_value(value)
          keepable = [true, false].include?(value) || value.is_a?(Condition) || value.is_a?(Integer) || value.is_a?(Value)
          keepable ? keep_side_value(value) : close_side(value)
        end

        def tail_value = @kept

        # A side of `x = test ? a : b` on a game variable: the number goes straight into x.
        def store_side(target, value)
          PlainRubySteps.assign(target, value)
          @condition.close_branch
        end

        def picked_value
          return @kept if @other_side

          PlainRubySteps.refuse_game_code!("`x = if ...` needs an `else`. Without one, x has no number when " \
                                 "the test fails, and a game has no nil. To fix this, add an `else`.")
        end

        def refuse_jump!(word) = PlainRubySteps.refuse_jump!(word)
      end

      def refuse_jump!(word)
        refuse_game_code!("`#{word}` cannot leave code the game runs as it plays. This block only records " \
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

        # The block runs once it is known this is a game's loop, and before the loop opens.
        def go_round(&before_loop)
          return close_game_loop if @game_loop

          value = @test.call
          return @stops_when ? !value : !!value unless PlainRubySteps.game_test?(value)

          open_game_loop(value, &before_loop)
        end

        def game? = !@game_loop.nil?
        def hidden_variable(why, like: nil) = @game_loop.hidden_variable(why, like: like)

        def refuse_jump!(word)
          PlainRubySteps.refuse_jump!(word) if @game_loop
        end

        private

        # A name given a variable by the block must be read as that variable from now on, in the
        # test too, or the loop would ask about the number it held before.
        def open_game_loop(value, &before_loop)
          @game_loop = stopping_test(value)
          if before_loop
            yield
            @game_loop.discard
            @game_loop = stopping_test(@test.call)
          end
          @game_loop.open_repeat(MOST_PASSES)
          true
        end

        def stopping_test(value)
          held = PlainRubySteps.as_condition(value)
          @stops_when ? held : !held
        end

        def close_game_loop
          @game_loop.close_repeat
          false
        end
      end
    end
  end
end
