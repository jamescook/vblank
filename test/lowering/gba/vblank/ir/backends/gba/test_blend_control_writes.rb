# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# WHAT THE BLEND UNIT IS TOLD, write by write, in a game whose light takes turns with a scene that
# mixes a layer. The console draws from whatever the register holds at that moment, and an
# interrupt can stop a pass for dozens of rows. So a pass that writes a value it means to replace
# can leave that value in force for part of a picture, and no reading taken once a frame would show
# it. Each pass has to say its last word and nothing before it.
class TestBlendControlWrites < Minitest::Test
  BLEND_CONTROL = VBlank::Console::Hardware::REG_BLDCNT
  DARKEN_EVERYTHING = 0xFF
  NOTHING = 0
  TURN = 6 # the pass the game changes scene on

  # A title that sees through water, and a scene with a light. The game starts in one and changes
  # to the other on pass 6.
  private def title_and_light(start_lit:)
    b = Builder.new
    b.instance_eval do
      screen :tiled
      layers :ground, :water
      image(:white_tile, "#" => :white) { (["#" * 8] * 8).join("\n") }
      image(:red_tile, "#" => :red) { (["#" * 8] * 8).join("\n") }
      tiles :set, "#" => :white_tile, "r" => :red_tile
      layer(:ground) { background :room, tiles: :set, map: ["#" * 32] * 32 }
      mode = var :mode, start_lit ? 1 : 0
      turn = var :turn, 0
      spotlight at: [120, 80], radius: 40, dark: 100
      scene(:title) { layer(:water, transparency: 50) { background :pond, tiles: :set, map: ["r" * 32] * 32 } }
      scene(:playing) {}
      game_loop do
        turn += 1
        mode = start_lit ? 0 : 1 if turn == TURN
        case_var(:mode) { when_val 0, :title; when_val 1, :playing }
      end
    end
    b.finalize_program
    b.program
  end

  # The values written to blend control, oldest first, once the game has been running a while.
  private def blend_control_values(program, name, frames:)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "blend.gba")
      assemble_rom(program, name: name).write(path)
      probe = VBlank::Diagnostics::Emulator.probe(path)
      probe.watch_display
      probe.step(frames)
      writes = probe.display_writes.select { |write| write.kind == :register && write.address == BLEND_CONTROL }
      probe.close
      writes.map(&:value)
    end
  end

  private def changes(values) = values.chunk_while { |a, b| a == b }.map(&:first)

  def test_a_lit_scene_only_ever_says_the_darkening
    values = blend_control_values(title_and_light(start_lit: false), "LIT", frames: 30)

    assert_equal [DARKEN_EVERYTHING], values.last(12).uniq
  end

  def test_the_light_comes_on_through_nothing_and_stays
    title_first = changes(blend_control_values(title_and_light(start_lit: false), "ARRIVE", frames: 30))

    assert_equal [NOTHING, DARKEN_EVERYTHING], title_first.last(2)
  end

  def test_a_scene_the_light_is_off_in_goes_straight_to_its_own_mixing
    lit_first = changes(blend_control_values(title_and_light(start_lit: true), "LEAVE", frames: 30))

    assert_equal DARKEN_EVERYTHING, lit_first[-2], "and never nothing on the way"
    refute_equal NOTHING, lit_first.last
  end
end
