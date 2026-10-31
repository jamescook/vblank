# frozen_string_literal: true

require "test_helper"

VBlank.require_game_file "../../../fixtures/game_with_two_parts/first"
VBlank.require_game_file "../../../plain_ruby_game_parts"

# What files of one game share when each is brought in by `VBlank.require_game_file`.
class TestPlainRubyParts < Minitest::Test
  def test_a_file_keeps_its_own_locals
    assert_equal 1, TWO_PARTS_SPEED
  end

  def test_a_constant_and_a_method_cross_between_files
    assert_equal 18, TWO_PARTS_ACROSS
  end

  private def played(part, *routines)
    builder = Builder.new
    part.new(builder)
    builder.game_loop { routines.each { |routine| builder.call(routine) } }
    builder.finalize_program
    player = game_player
    player.run(builder.program, frames: 3)
    player
  end

  def test_a_part_changes_a_name_made_by_its_builders_var
    assert_equal 3, played(CounterPart, :counter_tick)[:counter_count]
  end

  def test_a_part_fills_in_a_name_started_as_nil
    assert_equal 7, played(SparklePart, :sparkle_make)[:sparkle_glint]
  end

  def test_a_part_changes_a_plain_number_with_no_var_of_its_own
    assert_equal 6, played(TallyPart, :tally_tick, :tally_show)[:tally_seen]
  end

  def test_two_of_one_part_each_keep_their_own_number
    builder = Builder.new
    SeveralOfOnePart.new(builder, :first_tick)
    SeveralOfOnePart.new(builder, :second_tick)
    builder.game_loop do
      builder.call(:first_tick)
      builder.call(:first_tick)
      builder.call(:second_tick)
    end
    builder.finalize_program
    player = game_player
    player.run(builder.program, frames: 2)

    assert_equal [4, 2], [player[:ticks], player[:ticks_2]]
  end

  def test_a_part_changes_names_unpacked_from_its_builders_var
    player = played(TwoNamesPart, :unpacked_tick)

    assert_equal [4, 4], [player[:unpacked_first], player[:unpacked_second]]
  end
end
