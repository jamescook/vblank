# frozen_string_literal: true

require "test_helper"

VBlank.require_game_file "../../../plain_ruby_helper_part"

# A game block written in normal Ruby, the way an author sees it: each test plays a tiny game
# and reads the variables it leaves, on every lowering. What a line is rewritten into is
# test_plain_ruby_rewrite.rb's business, and what is refused test_plain_ruby_refusals.rb's.
class TestPlainRuby < Minitest::Test
  # Plays the block, rewritten, for +frames+ frames and hands back the player.
  private def played(frames: 3, allow: [], &block)
    builder = Builder.new
    builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(block, allow: allow))
    builder.finalize_program
    player = game_player
    player.run(builder.program, frames: frames)
    player
  end

  def test_if_runs_only_the_branch_whose_test_holds_as_the_game_plays
    player = played do
      hp = 0
      yes = 0
      no = 0
      game_loop do
        if hp == 0
          yes += 1
        else
          no += 1
        end
        hp += 1
      end
    end

    assert_equal 1, player[:yes]
    assert_operator player[:no], :>=, 1
  end

  def test_if_with_no_else_and_elsif_pick_one_side
    player = played(frames: 6) do
      n = 0
      a = 0
      b = 0
      c = 0
      d = 0
      game_loop do
        d += 1 if n == 0
        if n == 1
          a += 1
        elsif n == 2
          b += 1
        else
          c += 1
        end
        n += 1
      end
    end

    assert_equal [1, 1, 1], [player[:d], player[:a], player[:b]]
    assert_operator player[:c], :>=, 2
  end

  def test_a_ternary_used_as_a_statement_branches_too
    player = played(frames: 2) do
      n = 0
      a = 0
      b = 0
      game_loop do
        n == 0 ? a = 7 : b = 9
        n += 1
      end
    end

    assert_equal [7, 9], [player[:a], player[:b]]
  end

  def test_unless_and_trailing_unless_run_when_the_test_fails
    player = played(frames: 2) do
      n = 1
      a = 0
      b = 0
      game_loop do
        a = 5 unless n == 0
        unless n == 1
          b = 6
        else
          b = 7
        end
        n = 1
      end
    end

    assert_equal [5, 7], [player[:a], player[:b]]
  end

  def test_true_and_false_are_a_yes_or_no_the_game_keeps
    player = played(frames: 3) do
      alive = true
      hit = false
      drawn = 0
      skipped = 0
      game_loop do
        if alive
          drawn += 1
        else
          skipped += 1
        end
        alive = false if hit
        hit = true
      end
    end

    assert_operator player[:drawn], :>=, 1
    assert_operator player[:skipped], :>=, 1
  end

  def test_not_and_unless_and_joined_tests_read_a_yes_or_no
    player = played(frames: 1) do
      open = false
      lit = true
      a = 0
      b = 0
      c = 0
      game_loop do
        a = 1 unless open
        b = 1 if !open && lit
        c = 1 if open || lit
        open = false
      end
    end

    assert_equal [1, 1, 1], [player[:a], player[:b], player[:c]]
  end

  def test_a_yes_or_no_can_take_the_answer_of_a_test
    player = played(frames: 2) do
      hp = 3
      low = false
      seen = 0
      game_loop do
        low = hp < 5
        seen = 1 if low
        hp += 0
      end
    end

    assert_equal 1, player[:seen]
  end

  def test_a_picked_yes_or_no_is_a_yes_or_no
    player = played(frames: 2) do
      hp = 3
      seen = 0
      game_loop do
        low = hp < 5 ? true : false
        seen = 1 if low
        hp += 0
      end
    end

    assert_equal 1, player[:seen]
  end

  def test_a_copy_of_a_yes_or_no_is_a_yes_or_no
    player = played(frames: 2) do
      lit = true
      seen = 0
      game_loop do
        old = lit
        lit = false
        seen = 1 if old
        lit = true
      end
    end

    assert_equal 1, player[:seen]
  end

  # Truthiness is Ruby's: nil and false are falsy, and everything else is truthy. A number is
  # truthy whatever it holds, here as anywhere.
  def test_a_number_is_truthy_even_at_zero
    player = played(frames: 2) do
      hp = 0
      flags = 0
      plain = 0
      seen = 0
      worked_out = 0
      plain_seen = 0
      game_loop do
        seen = 1 if hp
        worked_out = 1 if flags & 4
        plain_seen = 1 if plain
        hp += 0
        flags += 0
      end
    end

    assert_equal [1, 1, 1], [player[:seen], player[:worked_out], player[:plain_seen]]
  end

  def test_nil_and_false_are_falsy_and_a_string_is_truthy
    player = played(frames: 2) do
      nothing = nil
      no = false
      words = "HI"
      a = 0
      b = 0
      c = 0
      game_loop do
        a = 1 if nothing
        b = 1 if no
        c = 1 if words
      end
    end

    assert_equal [0, 0, 1], [player[:a], player[:b], player[:c]]
  end

  def test_or_keeps_a_number_as_ruby_does
    player = played(frames: 2) do
      hp = 5
      kept = 0
      game_loop do
        kept = hp || 9
        hp += 0
      end
    end

    assert_equal 5, player[:kept]
  end

  # Nothing passed, true and false are three answers, and it takes `nil?` to tell the first from
  # the last, as in any Ruby.
  def test_nil_and_a_yes_or_no_are_three_answers
    player = played(frames: 2) do
      def mark(tally, tested = nil)
        if tested.nil?
          tally[:left_out] += 1
        elsif tested
          tally[:yes] += 1
        else
          tally[:no] += 1
        end
      end
      tally = { left_out: var(:left_out, 0), yes: var(:yes, 0), no: var(:no, 0) }
      on = true
      off = false
      game_loop do
        mark(tally)
        mark(tally, on)
        mark(tally, off)
        on = true
        off = false
      end
    end

    assert_equal player[:left_out], player[:yes]
    assert_equal player[:left_out], player[:no]
  end

  PLAYING = 2
  OVER = 3
  WIDE = 40
  TITLE_WORDS = "HI"

  def test_a_name_started_from_a_constant_is_a_variable
    player = played(frames: 2) do
      state = PLAYING
      game_loop { state = OVER }
    end

    assert_equal OVER, player[:state]
  end

  def test_a_name_started_from_a_sum_of_constants_is_a_variable
    player = played(frames: 2) do
      x = WIDE / 2
      seen = 0
      game_loop do
        seen = x
        x += 1
      end
    end

    assert_operator player[:seen], :>=, 20
  end

  def test_a_name_started_from_a_constant_that_is_no_number_stays_plain_ruby
    player = played(frames: 2) do
      words = TITLE_WORDS
      seen = 0
      game_loop do
        seen = 1 if words == "HI"
        words = TITLE_WORDS
      end
    end

    assert_equal 1, player[:seen]
  end

  # `recording or next` must leave the loop's own block, not one the rewrite made.
  def test_or_next_skips_the_rest_of_a_plain_ruby_block
    player = played(frames: 1) do
      count = 0
      [1, nil, 3].each do |each_number|
        kept = each_number or next
        count += kept
      end
      total = var :total, count
      game_loop { total += 0 }
    end

    assert_equal 4, player[:total]
  end

  def test_or_break_leaves_a_plain_ruby_block
    player = played(frames: 1) do
      count = 0
      [1, nil, 3].each do |each_number|
        kept = each_number || break
        count += kept
      end
      total = var :total, count
      game_loop { total += 0 }
    end

    assert_equal 1, player[:total]
  end

  def test_and_next_skips_the_rest_of_a_plain_ruby_block
    player = played(frames: 1) do
      count = 0
      [1, 2, 3].each do |each_number|
        each_number == 2 and next
        count += each_number
      end
      total = var :total, count
      game_loop { total += 0 }
    end

    assert_equal 4, player[:total]
  end

  def test_or_return_leaves_a_method
    player = played(frames: 1) do
      def first_given(one) = one || (return 9)
      total = var :total, first_given(nil)
      game_loop { total += 0 }
    end

    assert_equal 9, player[:total]
  end

  def test_the_right_of_and_runs_only_when_the_left_holds
    player = played(frames: 3) do
      n = 0
      seen = 0
      game_loop do
        (n == 99) && (seen += 1)
        n += 1
      end
    end

    assert_equal 0, player[:seen]
  end

  def test_a_test_whose_right_side_does_game_work_is_answered_by_both_sides
    player = played(frames: 3) do
      a = var :a, 5
      count = 0
      both = 0
      left_failed = 0
      right_failed = 0
      game_loop do
        both = 1 if a > 1 && (count += 1) > 0
        left_failed = 1 if a > 9 && (count += 1) > 0
        right_failed = 1 if a > 1 && (count += 1) > 99
      end
    end

    assert_equal [1, 0, 0], %i[both left_failed right_failed].map { |name| player[name] }
    assert_equal 6, player[:count]
  end

  def test_an_either_test_whose_right_side_does_game_work_is_answered_by_both_sides
    player = played(frames: 3) do
      a = var :a, 5
      count = 0
      left_held = 0
      right_held = 0
      neither = 0
      game_loop do
        left_held = 1 if a > 1 || (count += 1) > 0
        right_held = 1 if a > 9 || (count += 1) > 0
        neither = 1 if a > 9 || (count += 1) > 99
      end
    end

    assert_equal [1, 1, 0], %i[left_held right_held neither].map { |name| player[name] }
    assert_equal 6, player[:count]
  end

  def test_a_join_kept_in_a_name_holds_the_answer_of_a_right_side_doing_game_work
    player = played(frames: 2) do
      a = var :a, 5
      count = 0
      seen = 0
      game_loop do
        done = a > 1 && (count += 1) > 0
        seen = 1 if done
      end
    end

    assert_equal 1, player[:seen]
  end

  def test_the_right_of_and_skips_a_list_read_the_left_rules_out
    player = played(frames: 2) do
      things = list :things, capacity: 4, full_of: 0
      things[1] = 7
      i = var :i, 9
      ok = true
      skipped = 1
      found = 0
      game_loop do
        skipped = 0 if i < 4 && things[i] == 0
        i = 1 if i == 9
        found = 1 if ok && things[i] == 7
      end
    end

    assert_equal [1, 1], [player[:skipped], player[:found]]
  end

  def test_the_right_of_or_skips_a_list_read_the_left_decides
    player = played(frames: 1) do
      things = list :things, capacity: 4, full_of: 0
      i = var :i, 9
      seen = 0
      game_loop { seen = 1 if i >= 4 || things[i] == 0 }
    end

    assert_equal 1, player[:seen]
  end

  def test_a_number_changed_under_a_game_test_in_setup_follows_the_test
    player = played do
      hp = var :hp, 5
      taken = 1
      taken = 2 if hp > 3
      left = 1
      left = 2 if hp > 9
      seen_taken = 0
      seen_left = 0
      game_loop do
        seen_taken = taken
        seen_left = left
      end
    end

    assert_equal [2, 1], [player[:seen_taken], player[:seen_left]]
  end

  def test_a_number_changed_under_a_game_test_in_a_method_follows_the_test
    player = played do
      def speed_for(hp)
        s = 1
        before = s
        s = 2 if hp > 3
        s += before
        s
      end
      hp = var :hp, 5
      low = var :low, 1
      seen = 0
      seen_low = 0
      game_loop do
        seen = speed_for(hp)
        seen_low = speed_for(low)
      end
    end

    assert_equal [3, 2], [player[:seen], player[:seen_low]]
  end

  def test_a_name_first_given_a_number_on_both_sides_of_a_game_test_follows_the_test
    player = played do
      hp = var :hp, 5
      seen = 0
      game_loop do
        if hp > 3
          picked = 1
        else
          picked = 2
        end
        seen = picked
      end
    end

    assert_equal 1, player[:seen]
  end

  def test_an_argument_changed_under_a_game_test_follows_the_test
    player = played do
      def later_of(pose, passes)
        pose = 7 if passes >= 2
        pose
      end
      passes = 0
      seen = 0
      game_loop do
        passes += 1
        seen = later_of(1, passes)
      end
    end

    assert_equal 7, player[:seen]
  end

  def test_a_number_changed_in_a_game_loop_inside_a_method_follows_the_test
    player = played do
      def count_up(limit)
        n = 0
        while n < limit
          n += 1
        end
        n
      end
      limit = var :limit, 3
      seen = 0
      game_loop { seen = count_up(limit) }
    end

    assert_equal 3, player[:seen]
  end

  def test_a_name_only_used_under_a_game_test_costs_no_variable
    builder = Builder.new
    builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(proc do
      hp = var :hp, 5
      seen = 0
      game_loop do
        if hp > 3
          worked = hp + 1
          worked += 1
          seen = worked
        end
      end
    end))
    builder.finalize_program

    refute_includes builder.program.walk.select { |node| node.kind == :var_ref }.map(&:name), :__kept_1
  end

  def test_the_right_of_or_runs_only_when_the_left_fails
    player = played(frames: 3) do
      n = 0
      seen = 0
      game_loop do
        (n == 0) || (seen += 1)
        n += 1
      end
    end

    assert_operator player[:seen], :>=, 1
    assert_operator player[:seen], :<, player[:n]
  end

  def test_two_tests_joined_still_make_one_test
    player = played(frames: 2) do
      hp = 3
      both = 0
      either = 0
      game_loop do
        both = 1 if hp > 1 && hp < 9
        either = 1 if hp > 9 || hp < 9
        hp += 0
      end
    end

    assert_equal [1, 1], [player[:both], player[:either]]
  end

  def test_an_ivar_given_another_variable_moves_to_it
    player = played(frames: 2) do
      a = var :a, 1
      b = var :b, 2
      @focus = a
      seen = 0
      game_loop do
        @focus = b
        seen = @focus
        a += 0
        b += 0
      end
    end

    assert_equal [1, 2], [player[:a], player[:seen]]
  end

  def test_a_light_moved_to_two_variables_takes_their_numbers
    player = played(frames: 2) do
      screen :tiled
      light = spotlight at: [0, 0], radius: 8, dark: 50
      x = 30
      y = 40
      seen_x = 0
      seen_y = 0
      game_loop do
        light.move_to x, y
        seen_x = light.x
        seen_y = light.y
        x += 0
        y += 0
      end
    end

    assert_equal [30, 40], [player[:seen_x], player[:seen_y]]
  end

  def test_a_picked_value_in_parentheses_is_kept
    player = played(frames: 2) do
      hp = 3
      y = 0
      game_loop do
        y = (hp > 3 ? 2 : 7)
        hp += 0
      end
    end

    assert_equal 7, player[:y]
  end

  def test_begin_end_while_runs_its_body_first
    player = played(frames: 1) do
      count = 0
      begin
        count += 1
      end while count > 5
      total = var :total, count
      game_loop { total += 0 }
    end

    assert_equal 1, player[:total]
  end

  def test_or_equals_sets_a_yes_or_no_that_is_false
    player = played(frames: 3) do
      n = 0
      latched = false
      game_loop do
        latched ||= n == 0
        n += 1
      end
    end

    assert_equal 1, player[:latched]
  end

  def test_or_equals_leaves_a_number_alone_as_it_is_truthy
    player = played(frames: 2) do
      n = 5
      game_loop do
        n ||= 9
        n += 0
      end
    end

    assert_equal 5, player[:n]
  end

  def test_a_name_started_from_a_symbol_is_a_variable
    player = played(frames: 2) do
      mode = :title
      seen = 0
      game_loop do
        seen = 1 if mode == :playing
        mode = :playing
      end
    end

    assert_equal 1, player[:seen]
  end

  NEGATIVE = -4

  def test_a_name_started_from_a_constant_turned_round_is_a_variable
    player = played(frames: 2) do
      x = -NEGATIVE
      y = NEGATIVE.abs
      game_loop do
        x += 1
        y += 1
      end
    end

    assert_operator player[:x], :>, 4
    assert_operator player[:y], :>, 4
  end

  def test_a_number_handed_in_is_truthy_even_at_zero
    player = played(frames: 2) do
      def count_if_there(tally, by)
        tally[:seen] += 1 if by
      end
      zero = var :zero, 0
      tally = { seen: var(:seen, 0) }
      game_loop { count_if_there(tally, zero) }
    end

    assert_operator player[:seen], :>=, 1
  end

  Held = Data.define(:number)

  def test_a_number_kept_in_an_object_is_truthy_even_at_zero
    player = played(frames: 2) do
      held = Held.new(number: var(:zero, 0))
      seen = 0
      game_loop { seen = 1 if held.number }
    end

    assert_equal 1, player[:seen]
  end

  def test_and_or_not_combine_tests_anywhere_a_test_is_made
    player = played(frames: 2) do
      n = 3
      both = 0
      either = 0
      neither = 0
      kept = 0
      game_loop do
        both = 1 if n > 2 && n < 4
        either = 1 if n == 0 || n == 3
        neither = 1 if !(n == 0) && !(n == 1)
        high = n > 2
        low = n < 1
        kept = 1 if high && !low
        kept = 2 if high && low
        n = 3
      end
    end

    assert_equal [1, 1, 1, 1], [player[:both], player[:either], player[:neither], player[:kept]]
  end

  def test_a_plain_value_beside_a_game_test_decides_at_build_time
    open_door = true
    shut_door = false
    player = played(frames: 2) do
      n = 3
      a = 0
      b = 0
      game_loop do
        a = 1 if n == 3 && open_door
        b = 1 if n == 3 && shut_door
        n = 3
      end
    end

    assert_equal [1, 0], [player[:a], player[:b]]
  end

  def test_while_loops_on_a_game_test_and_skips_a_test_already_false
    player = played(frames: 2) do
      n = 4
      m = 0
      passes = 0
      none = 0
      game_loop do
        while n > 0
          n -= 1
          passes += 1
        end
        while m > 0
          none += 1
          m -= 1
        end
      end
    end

    assert_equal 4, player[:passes]
    assert_equal 0, player[:none]
  end

  def test_a_wait_inside_a_while_lets_frames_pass_while_it_goes_round
    player = played(frames: 4) do
      n = 0
      after = 0
      game_loop do
        while n < 100
          n += 1
          wait_vblank
        end
        after = 1
      end
    end

    assert_operator player[:n], :<, 10
    assert_equal 0, player[:after]
  end

  def test_until_stops_once_the_test_holds
    player = played(frames: 2) do
      n = 0
      game_loop do
        until n >= 3
          n += 1
        end
      end
    end

    assert_equal 3, player[:n]
  end

  def test_conditionals_on_plain_values_stay_plain_ruby
    player = played(frames: 2) do
      count = 0
      count += 1 while count < 3
      picked = if count == 3 then 10 else 20 end
      kept = count > 100 ? 1 : 2
      shown = 0
      game_loop { shown = picked + kept }
    end

    assert_equal 12, player[:shown]
  end

  def test_a_local_first_set_in_a_build_time_branch_outlives_it
    player = played(frames: 2) do
      if screen_width > 0
        wide = 8
      end
      shown = 0
      game_loop { shown = wide }
    end

    assert_equal 8, player[:shown]
  end

  def test_a_heredoc_inside_a_branch_keeps_its_lines_once_each
    player = played(frames: 1) do
      rows = 0
      if screen_width > 0
        art = <<~ART
          one
          two
        ART
        rows = art.lines.length
      end
      shown = 0
      game_loop { shown = rows }
    end

    assert_equal 2, player[:shown]
  end

  def test_every_changing_operator_changes_the_real_variable
    player = played(frames: 1) do
      added = 5
      taken = 5
      timed = 5
      bits = 5
      game_loop do
        added += 2
        taken -= 2
        timed *= 2
        bits |= 2
      end
    end

    assert_equal [7, 3, 10, 7], [player[:added], player[:taken], player[:timed], player[:bits]]
  end

  def test_a_game_variable_kept_in_a_hash_or_array_is_changed_where_it_stands
    player = played(frames: 1) do
      ball = { x: var(:x, 1), y: var(:y, 1) }
      pair = [var(:first, 1), var(:second, 1)]
      game_loop do
        ball[:x] = 5
        ball[:y] += 2
        pair[0] = 7
        pair[1] -= 1
      end
    end

    assert_equal [5, 3, 7, 0], [player[:x], player[:y], player[:first], player[:second]]
  end

  def test_a_plain_hash_and_array_stay_plain
    player = played(frames: 1) do
      sizes = { wide: 1 }
      sizes[:wide] += 2
      sizes[:tall] = 4
      shown = 0
      game_loop { shown = sizes[:wide] + sizes[:tall] }
    end

    assert_equal 7, player[:shown]
  end

  def test_a_field_of_a_sprite_or_pool_is_set_like_a_variable
    player = played(frames: 1) do
      screen :tiled
      image(:hero, "#" => :red) { (["########"] * 8).join("\n") }
      hero = sprite :hero, at: [10, 20]
      shown = 0
      game_loop do
        hero.x = 30
        hero.y += 5
        shown = hero.x + hero.y
      end
    end

    assert_equal 55, player[:shown]
  end

  def test_a_list_slot_is_set_as_it_always_was
    player = played(frames: 1) do
      things = list :things, capacity: 2, full_of: 0
      shown = 0
      game_loop do
        things[0] = 3
        things[0] += 1
        shown = things[0]
      end
    end

    assert_equal 4, player[:shown]
  end

  def test_a_number_changed_inside_a_pools_each_in_the_game_loop_is_a_variable
    player = played(frames: 1) do
      sparks = pool(:spark, x: 0, capacity: 3)
      count = 0
      game_loop do
        sparks.spawn(x: 1)
        sparks.spawn(x: 2)
        sparks.each { count += 1 }
      end
    end

    assert_equal 2, player[:count]
  end

  def test_a_number_changed_by_a_menu_row_is_a_variable
    builder = Builder.new
    builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(proc do
      picked = 0
      game_loop { menu(:main, at: [40, 40], press: :a) { |rows| rows.item("GO") { picked = 7 } } }
    end))
    builder.finalize_program
    player = game_player
    player.hold(:a)
    player.run(builder.program, frames: 3)

    assert_equal 7, player[:picked]
  end

  def test_a_block_a_test_hands_to_instance_exec_is_read_as_normal_ruby
    extra = proc { |hp| hp.add! 1 if hp == 0 }
    builder = Builder.new
    builder.instance_eval do
      hp = var :hp, 0
      game_loop { instance_exec(hp, &extra) }
    end
    builder.finalize_program
    player = game_player
    player.run(builder.program, frames: 3)

    assert_equal 1, player[:hp]
  end

  def test_a_lambda_a_test_hands_to_instance_exec_is_read_as_normal_ruby
    extra = ->(hp) { hp.add! 1 if hp == 0 }
    builder = Builder.new
    builder.instance_eval do
      hp = var :hp, 0
      game_loop { instance_exec(hp, &extra) }
    end
    builder.finalize_program
    player = game_player
    player.run(builder.program, frames: 3)

    assert_equal 1, player[:hp]
  end

  def test_bit_operators_join_tests_as_ruby_does_on_true_and_false
    player = played do
      a = var :a, 5
      both = 0
      neither = 0
      either = 0
      one = 0
      game_loop do
        both = 1 if (a > 1) & (a < 9)
        neither = 1 if (a > 1) & (a > 9)
        either = 1 if (a > 9) | (a > 1)
        one = 1 if (a > 1) ^ (a > 9)
      end
    end

    assert_equal [1, 0, 1, 1], %i[both neither either one].map { |name| player[name] }
  end

  def test_a_bit_operator_works_out_both_sides
    player = played do
      a = var :a, 5
      n = 0
      seen = 0
      game_loop { seen = 1 if (a > 9) & ((n += 1) > 0) }
    end

    assert_equal 0, player[:seen]
    assert_equal 3, player[:n]
  end

  def test_a_bit_operator_beside_a_plain_true_or_false_leaves_the_test
    player = played do
      a = var :a, 5
      yes = true
      no = false
      kept = 0
      dropped = 0
      given = 0
      number = 0
      game_loop do
        kept = 1 if yes & (a > 1)
        dropped = 1 if no & (a > 1)
        given = 1 if no | (a > 1)
        number = 1 if (a > 1) & a
      end
    end

    assert_equal [1, 0, 1, 1], %i[kept dropped given number].map { |name| player[name] }
  end

  def test_bit_assignment_changes_a_yes_or_no
    player = played do
      a = var :a, 5
      lost = true
      held = true
      game_loop do
        lost &= a > 9
        held &= a > 1
      end
    end

    assert_equal [0, 1], [player[:lost], player[:held]]
  end

  def test_a_number_given_to_a_methods_argument_leaves_the_caller_alone
    player = played do
      def set_to_nine(hp)
        hp = 9
        hp
      end
      hp = var :hp, 0
      seen = 0
      game_loop do
        seen = set_to_nine(hp)
      end
    end

    assert_equal [0, 9], [player[:hp], player[:seen]]
  end

  def test_adding_to_a_methods_argument_leaves_the_caller_alone
    player = played do
      def plus_ten(hp)
        hp += 10
        hp
      end
      hp = var :hp, 5
      seen = 0
      game_loop do
        seen = plus_ten(hp)
      end
    end

    assert_equal [5, 15], [player[:hp], player[:seen]]
  end

  def test_a_number_given_to_a_name_taken_from_a_hash_leaves_the_hash_alone
    player = played do
      ball = { hp: var(:hp, 5) }
      seen = 0
      game_loop do
        hp = ball[:hp]
        hp = 2
        seen = hp
      end
    end

    assert_equal [5, 2], [player[:hp], player[:seen]]
  end

  def test_adding_to_a_name_taken_from_a_hash_leaves_the_hash_alone
    player = played do
      ball = { hx: var(:hx, 5) }
      seen = 0
      game_loop do
        nx = ball[:hx]
        nx += 10
        seen = nx
      end
    end

    assert_equal [5, 15], [player[:hx], player[:seen]]
  end

  def test_a_name_started_from_another_local_is_a_game_variable
    player = played do
      start = 10
      x = start
      game_loop { x += 1 }
    end

    assert_equal 13, player[:x]
  end

  SIZES = [4, 8].freeze

  def test_a_name_started_from_a_method_or_a_list_is_a_game_variable
    player = played do
      def worked_out_start = 20
      from_method = worked_out_start
      from_list = SIZES[1]
      half = screen_width / 2
      game_loop do
        from_method += 1
        from_list += 1
        half += 1
      end
    end

    assert_equal [23, 11, 123], [player[:from_method], player[:from_list], player[:half]]
  end

  def test_a_start_with_an_effect_runs_once
    player = played do
      count = [0]
      def next_start(count) = count[0] += 1
      x = next_start(count)
      runs = count[0]
      seen = 0
      game_loop do
        x += 1
        seen = runs
      end
    end

    assert_equal [4, 1], [player[:x], player[:seen]]
  end

  def test_a_name_started_from_a_variable_and_changed_is_its_own_variable
    player = played do
      hp = var :hp, 5
      other = hp
      game_loop { other += 1 }
    end

    assert_equal [5, 8], [player[:hp], player[:other]]
  end

  def test_a_name_started_from_a_test_and_changed_keeps_a_yes_or_no
    player = played do
      hp = var :hp, 5
      alive = hp > 0
      seen = 0
      game_loop do
        alive = false
        seen = 1 if alive
      end
    end

    assert_equal 0, player[:seen]
  end

  # `if by` on an option asks what Ruby asks, whether it was given, even when what was given is a
  # game variable holding 0.
  def test_an_option_in_an_if_asks_whether_it_was_given
    player = played(frames: 2) do
      def count_if_given(tally, key, by: nil)
        tally[key] += 1 if by
      end
      zero = var :zero, 0
      tally = { given: var(:given, 0), left_out: var(:left_out, 0) }
      game_loop do
        count_if_given(tally, :given, by: zero)
        count_if_given(tally, :left_out)
      end
    end

    assert_operator player[:given], :>=, 1
    assert_equal 0, player[:left_out]
  end

  def test_a_number_added_up_over_a_list_written_out_in_ruby_stays_a_number
    player = played(frames: 2) do
      shown = 0
      game_loop do
        total = 0
        [1, 2, 3].each { |each_number| total += each_number }
        shown = total
      end
    end

    assert_equal 6, player[:shown]
  end

  def test_a_number_changed_under_a_game_test_inside_ruby_iteration_is_a_variable
    player = played(frames: 1) do
      n = 2
      hits = 0
      game_loop do
        [1, 2, 3].each { |each_number| hits += 1 if n == each_number }
      end
    end

    assert_equal 1, player[:hits]
  end

  def test_a_list_slot_at_a_fixed_place_can_stand_on_the_right_of_and
    player = played(frames: 1) do
      things = list :things, capacity: 2, full_of: 1
      n = 3
      found = 0
      game_loop do
        found = 1 if n == 3 && things[1] == 1
      end
    end

    assert_equal 1, player[:found]
  end

  def test_a_list_read_with_an_index_the_left_side_did_not_test_is_allowed
    player = played(frames: 1) do
      things = list :things, capacity: 2, full_of: 1
      i = 1
      n = 3
      found = 0
      game_loop do
        found = 1 if n == 3 && things[i] == 1
        i = 1
      end
    end

    assert_equal 1, player[:found]
  end

  def test_a_call_without_parentheses_can_be_assigned_to_a_name_set_before
    player = played(frames: 1) do
      shown = 0
      numbers = nil
      numbers = Array.new 2 do |each_slot| each_slot + 4 end
      total = 0
      total += numbers.sum do |each_number| each_number end
      game_loop { shown = total }
    end

    assert_equal 9, player[:shown]
  end

  def test_a_game_part_keeps_its_frozen_strings_and_its_line_numbers
    assert_predicate PlainRubyHelperPart::NAME, :frozen?
    assert_equal 8, PlainRubyHelperPart::WRITTEN_ON
  end

  def test_a_game_part_in_a_file_of_its_own_can_be_written_in_normal_ruby
    player = played(frames: 5, allow: %w[PlainRubyHelperPart]) do
      part = PlainRubyHelperPart.new(self)
      game_loop { part.step }
    end

    assert_equal 3, player[:part_count]
    assert_equal 9, player[:part_flips]
  end

  def test_assignment_changes_a_variable_made_with_var
    player = played(frames: 2) do
      hp = var :hp, 5
      game_loop { hp = hp + 1 }
    end

    assert_operator player[:hp], :>, 5
  end

  def test_a_second_name_for_a_variable_can_move_to_another
    player = played(frames: 1) do
      hero_x = var :hero_x, 1
      enemy_x = var :enemy_x, 2
      target = hero_x
      target = enemy_x
      shown = 0
      game_loop { shown = target }
    end

    assert_equal 2, player[:shown]
    assert_equal 1, player[:hero_x]
  end

  def test_a_picked_value_is_worked_out_at_its_line_on_every_pass
    player = played(frames: 3) do
      n = 0
      first = 0
      other = 0
      game_loop do
        x = n == 0 ? 10 : 20
        y = if n == 0 then 1 elsif n == 1 then 2 else 3 end
        first = x + y if n == 0
        other = x + y if n == 1
        n += 1
      end
    end

    assert_equal [11, 22], [player[:first], player[:other]]
  end

  def test_a_picked_value_keeps_its_answer_after_the_test_changes
    player = played(frames: 1) do
      n = 0
      shown = 0
      game_loop do
        x = n == 0 ? 10 : 20
        n = 5
        shown = x
      end
    end

    assert_equal 10, player[:shown]
  end

  def test_a_copy_made_while_playing_keeps_the_old_value
    player = played(frames: 1) do
      hp = 5
      old = 0
      game_loop do
        before = hp
        hp = 3
        old = before
      end
    end

    assert_equal [3, 5], [player[:hp], player[:old]]
  end

  def test_a_name_set_in_the_game_loop_starts_afresh_each_pass
    player = played(frames: 4) do
      shown = 0
      game_loop do
        count = 0
        count += 1
        shown = count
      end
    end

    assert_equal 1, player[:shown]
  end

  def test_the_same_name_in_two_routines_is_two_variables
    player = played(frames: 1) do
      shown = 0
      func(:one) { x = 1; x += 1; shown += x }
      func(:two) { x = 10; x += 1; shown += x }
      game_loop do
        shown = 0
        call :one
        call :two
      end
    end

    assert_equal 13, player[:shown]
  end
end
