# frozen_string_literal: true

require "stringio"
require "test_helper"

# A `while` the game runs stops the picture and the buttons until it ends, unless something in it
# waits for the next frame, so one that never does earns a warning.
class TestIRGuardrailLoopNeverWaits < Minitest::Test
  private def warnings_of(frame_sync: :auto, &block)
    err = StringIO.new
    VBlank.build("PLAIN", console: :gba, frame_sync: frame_sync, out: StringIO.new, err: err, &block)
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
    said = warnings_of(frame_sync: :manual) do
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

    refute_includes said, "never waits for the next frame"
  end
end
