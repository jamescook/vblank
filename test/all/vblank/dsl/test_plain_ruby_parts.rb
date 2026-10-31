# frozen_string_literal: true

require "test_helper"

VBlank.require_game_file "../../../fixtures/game_with_two_parts/first"

# What files of one game share when each is brought in by `VBlank.require_game_file`.
class TestPlainRubyParts < Minitest::Test
  def test_a_file_keeps_its_own_locals
    assert_equal 1, TWO_PARTS_SPEED
  end

  def test_a_constant_and_a_method_cross_between_files
    assert_equal 18, TWO_PARTS_ACROSS
  end
end
