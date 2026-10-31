# frozen_string_literal: true

require "stringio"
require "test_helper"
require "fixtures/game_with_plain_helper/game"
require "fixtures/game_with_plain_data/game"

# What a game block in normal Ruby cannot do, and the plain words an author gets instead.
class TestPlainRubyRefusals < Minitest::Test
  OWN_NUMBER = 7

  Refused = VBlank::DSL::PlainRuby::Refused

  # Read from each test's Ractor, as an example's game is.
  SHARED_GAME = VBlank.game("SHARED", consoles: %i[gba]) do
    hp = 3
    game_loop { hp -= 1 if hp > OWN_NUMBER - 7 }
  end

  private def built(allow: [], &block)
    builder = Builder.new
    builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(block, allow: allow))
    builder.finalize_program
    builder
  end

  private def assert_refused(phrase, &block)
    error = assert_raises(Refused) { built(&block) }
    assert_includes error.message, phrase
  end

  def test_a_constant_from_outside_the_game_is_refused_and_points_above_the_block
    assert_refused("above the block") { game_loop { Net::HTTP.get("example.com", "/") } }
    assert_refused("`File`") { File.read("level.txt") }
    assert_refused("`Minitest`") { game_loop { Minitest::Test } }
  end

  def test_a_gem_nobody_has_heard_of_is_refused_the_same_way
    assert_refused("`SomeGemNobodyListed`") { SomeGemNobodyListed.go }
  end

  def test_the_games_own_constants_and_ruby_basics_are_allowed
    builder = built do
      wall = Array.new(2, OWN_NUMBER)
      shown = 0
      game_loop { shown = wall.first + Math.sqrt(16).to_i }
    end

    assert_kind_of Builder, builder
  end

  def test_the_author_can_allow_a_library_at_their_own_risk
    builder = built(allow: %w[Minitest]) do
      Minitest::Test
      game_loop { wait_vblank }
    end

    assert_kind_of Builder, builder
  end

  def test_calls_that_reach_outside_the_game_are_refused
    assert_refused("`system`") { system("ls") }
    assert_refused("`require`") { require "json" }
    assert_refused("`eval`") { eval("1 + 1") }
    assert_refused("`send`") { 1.send(:+, 1) }
    assert_refused("Backticks") { `ls` }
  end

  def test_a_game_verb_named_like_one_of_rubys_outside_calls_is_allowed
    builder = built do
      sparks = pool(:spark, x: 0, capacity: 2)
      game_loop { sparks.spawn(x: 1) }
    end

    assert_kind_of Builder, builder
  end

  def test_a_warning_names_the_authors_own_line
    line = __LINE__ + 4
    said = warnings_of do
      n = 0
      game_loop do
        while n >= 0
          n += 1
        end
      end
    end

    assert_includes said, "test_plain_ruby_refusals.rb:#{line}"
  end

  def test_jumping_out_of_game_code_is_refused
    assert_refused("`break`") do
      n = 0
      game_loop { n += 1; while n > 0; break if n == 3; n -= 1; end }
    end
    assert_refused("`next`") do
      n = 0
      game_loop { if n == 3 then next end; n += 1 }
    end
    assert_refused("`return`") do
      n = 0
      game_loop { return if n == 3; n += 1 }
    end
  end

  def test_jumping_in_build_time_code_is_plain_ruby
    builder = built do
      wide = 0
      if wide == 0
        3.times { |each_time| next if each_time == 1; wide = each_time }
      end
      game_loop { wait_vblank }
    end

    assert_kind_of Builder, builder
  end

  def test_a_picked_value_must_be_a_number
    assert_refused("between numbers") do
      n = 0
      game_loop { x = n == 0 ? :left : :right; n += 1 }
    end
  end

  def test_a_picked_value_needs_an_else
    assert_refused("needs an `else`") do
      n = 0
      game_loop { x = if n == 0 then 1 end; n += 1 }
    end
  end

  def test_a_plain_number_changed_by_game_code_it_cannot_reach_is_refused
    assert_refused("`count`") do
      sparks = pool(:spark, x: 0, capacity: 3)
      count = 0
      sparks.each { count += 1 }
      game_loop { pixel count, 0, :red }
    end
  end

  def test_a_plain_number_counted_by_a_plain_ruby_block_is_left_alone
    builder = built do
      total = 0
      [1, 2, 3].each { |each_number| total += each_number }
      game_loop { pixel total, 0, :red }
    end

    assert_kind_of Builder, builder
  end

  def test_a_game_can_be_shared_between_ractors
    game = TestPlainRubyRefusals::SHARED_GAME

    assert_predicate game, :frozen?
    refute_empty game.program.children
  end

  def test_changing_a_method_argument_with_plus_equals_is_clear_enough_to_work
    builder = built do
      def hurt(hp) = (hp -= 1)
      hurt(var(:hp, 5))
      game_loop { wait_vblank }
    end

    assert_kind_of Builder, builder
  end

  def test_a_list_read_on_the_right_of_and_is_refused
    assert_refused("reads a list") do
      things = list :things, capacity: 4
      i = 0
      game_loop do
        i = 1 if i < 4 && things[i] == 1
      end
    end
  end

  private def warnings_of(&block)
    err = StringIO.new
    VBlank.build("PLAIN", console: :gba, out: StringIO.new, err: err, &VBlank::DSL::PlainRuby.rewrite(block))
    err.string
  end

  def test_a_while_with_no_frame_wait_warns
    said = warnings_of do
      n = 0
      game_loop do
        while n >= 0
          n += 1
        end
      end
    end

    assert_includes said, "never waits for the next frame"
  end

  def test_a_while_that_waits_does_not_warn
    said = warnings_of do
      n = 0
      game_loop do
        while n < 5
          n += 1
          wait_vblank
        end
      end
    end

    refute_includes said, "never waits for the next frame"
  end

  def test_a_while_that_waits_in_a_routine_it_calls_does_not_warn
    err = StringIO.new
    block = proc do
      n = 0
      func(:rest) { wait_vblank }
      game_loop do
        while n < 5
          n += 1
          call :rest
        end
        wait_vblank
      end
    end
    VBlank.build("PLAIN", console: :gba, frame_sync: :manual, out: StringIO.new, err: err,
                          &VBlank::DSL::PlainRuby.rewrite(block))

    refute_includes err.string, "never waits for the next frame"
  end

  def test_a_misspelt_key_on_a_hash_of_game_variables_is_refused
    assert_refused("no key :hq") do
      ball = { hp: var(:hp, 5) }
      game_loop { ball[:hq] = 2 }
    end
  end

  def test_a_new_key_on_a_plain_hash_is_plain_ruby
    built do
      ball = { hp: 5 }
      ball[:mp] = 2
      game_loop { wait_vblank }
    end
  end

  def test_a_number_tested_alone_builds_with_every_check_on
    rom = VBlank.build("TRUTHY", console: :gba, out: StringIO.new, err: StringIO.new) do
      flags = 3
      game_loop do
        wait_vblank if flags & 4
        flags += 1
      end
    end

    assert rom, "the game builds"
  end

  def test_unless_on_a_yes_or_no_builds_with_every_check_on
    rom = VBlank.build("YESNO", console: :gba, out: StringIO.new, err: StringIO.new) do
      lit = true
      game_loop do
        wait_vblank unless lit
        lit = false
      end
    end

    assert rom, "the game builds"
  end

  def test_a_flag_on_a_vblank_handle_is_a_test
    built do
      game_loop do
        rows = menu(:main, at: [40, 40]) { |row| row.item("GO") { wait_vblank } }
        wait_vblank if rows.moved
      end
    end
  end

  def test_a_file_of_game_code_brought_in_with_require_relative_is_refused
    error = assert_raises(Refused) { VBlank::DSL::PlainRuby.rewrite(GameWithPlainHelper.block) }

    assert_includes error.message, "`walker.rb` holds game code"
    assert_includes error.message, 'VBlank.require_game_file "walker"'
    assert_includes error.message, "game.rb:4"
  end

  def test_a_file_of_plain_ruby_can_come_in_with_require_relative
    assert_kind_of Proc, VBlank::DSL::PlainRuby.rewrite(GameWithPlainData.block)
  end

  def test_vblank_game_builds_a_game_written_in_plain_ruby
    game = VBlank.game("PLAIN GAME", consoles: %i[gba]) do
      shown = 0
      game_loop { shown += 1 if shown < 3 }
    end

    refute_empty game.program.children
  end
end
