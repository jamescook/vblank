# frozen_string_literal: true

require "test_helper"

# `func` and `call`: that a game of them builds, and the friendly errors for a misuse. The ARM
# they lower to, and a game of them run in the emulator, are in
# test/lowering/gba/vblank/builder/test_subroutines_cartridge.rb.

# How both files build a game.
module SubroutinesGames
  private def build(validate: false, &block)
    VBlank.build("SUBTEST", console: :gba, code: "BSUB", maker: "01", validate: validate, out: nil, err: nil, &block)
  end
end

class TestSubroutines < Minitest::Test
  include VBlank::Console::Hardware
  include SubroutinesGames

  # ========================================================================
  # Basic func/call
  # ========================================================================

  def test_func_and_call_builds
    rom = build do
      ball_x = 0
      ball_y = 0
      func :reset_ball do
        ball_x = 120
        ball_y = 80
      end

      call :reset_ball
      halt
    end

    assert_operator rom.size, :>, 0
  end

  def test_call_before_func_definition
    # Order shouldn't matter — call before func should work
    rom = build do
      ball_x = 0
      call :reset_ball
      halt

      func :reset_ball do
        ball_x = 120
      end
    end

    assert_operator rom.size, :>, 0
  end

  def test_multiple_calls_to_same_func
    rom = build do
      score = 0
      func :inc_score do
        score += 1
      end

      call :inc_score
      call :inc_score
      call :inc_score
      halt
    end

    assert_operator rom.size, :>, 0
  end

  # ========================================================================
  # Error cases
  # ========================================================================

  def test_duplicate_func_raises
    assert_raises(ArgumentError) do
      build do
        func :foo do; end
        func :foo do; end
      end
    end
  end

  def test_call_undefined_func_raises
    assert_raises(ArgumentError) do
      build do
        call :nonexistent
        halt
      end
    end
  end

  # ========================================================================
  # Func with game loop
  # ========================================================================

  def test_func_called_from_game_loop
    rom = build do
      screen :bitmap

      ball_x = 120
      func :update_ball do
        ball_x += 2
        ball_x = 0 if ball_x >= 240
      end

      game_loop do
        call :update_ball
      end
    end

    assert_operator rom.size, :>, 0
  end

  def test_func_calling_another_func
    rom = build do
      x = 0
      y = 0
      func :inner do
        x = 1
      end

      func :outer do
        call :inner
        y = 2
      end

      call :outer
      halt
    end

    assert_operator rom.size, :>, 0
  end
end
