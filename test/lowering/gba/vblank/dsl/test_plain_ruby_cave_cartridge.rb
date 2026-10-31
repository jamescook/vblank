# frozen_string_literal: true

require "test_helper"
require VBlank.root.join("examples", "cave.rb").to_s

# The two ways to write a game make the same cartridge, byte for byte. examples/cave.rb is in
# normal Ruby, and this is the same game with `VBlank.game`, `.then` and `var`, which stay.
class TestPlainRubyCaveCartridge < Minitest::Test
  private def block_form_cave
    VBlank.game("CAVE", consoles: %i[gba]) do
      screen :tiled

      image :rock, "#" => rgb(12, 10, 9), "." => rgb(7, 6, 5) do
        <<~ART
          .######.
          ########
          ###.####
          ########
          ####.###
          ########
          ##.#####
          .######.
        ART
      end

      image :floor, "." => rgb(14, 11, 7), "o" => rgb(18, 14, 9) do
        <<~ART
          ........
          ...o....
          ........
          ......o.
          ........
          .o......
          ........
          ....o...
        ART
      end

      image :grass, "," => rgb(6, 20, 6), "'" => rgb(10, 26, 8) do
        <<~ART
          ,,,,,,,,
          ,',,,,',
          ,,,,,,,,
          ,,,',,,,
          ,,,,,,,,
          ',,,,,',
          ,,,,,,,,
          ,,',,,,,
        ART
      end

      image :water, "~" => rgb(4, 10, 22), "-" => rgb(10, 18, 28) do
        <<~ART
          ~~~~~~~~
          ~--~~~~~
          ~~~~~~~~
          ~~~~~--~
          ~~~~~~~~
          ~~--~~~~
          ~~~~~~~~
          ~~~~~~--
        ART
      end

      image :hero, "." => :transparent, "o" => :yellow, "#" => :red do
        <<~ART
          ..oooo..
          ..oooo..
          ...oo...
          .######.
          #.####.#
          ..####..
          ..#..#..
          .##..##.
        ART
      end

      tiles :ground, "#" => :rock, "." => :floor, "," => :grass, "~" => :water, solid: ["#", "~"]
      land = background :land, tiles: :ground, map: { cave: Cave::CAVE, meadow: Cave::MEADOW }

      hero = sprite :hero, at: [24, Cave::CAVE_MOUTH_Y]
      hero.blocked_by land

      lantern = spotlight at: [28, Cave::CAVE_MOUTH_Y + 4], radius: Cave::LANTERN_REACH, dark: Cave::CAVE_DARK

      leaving = var :leaving, 0

      game_loop do
        (leaving == 0).then do
          held(:left).then { hero.move :left, by: 1 }
          held(:right).then { hero.move :right, by: 1 }
          held(:up).then { hero.move :up, by: 1 }
          held(:down).then { hero.move :down, by: 1 }
        end
        hero.clamp_to_screen
        lantern.move_to hero.x + 4, hero.y + 4

        in_cave = (land.showing == land.map_number(:cave))
        leaving_cave = in_cave & (hero.x >= Cave::CAVE_MOUTH_X)
        entering_cave = (land.showing == land.map_number(:meadow)) & (hero.x <= Cave::MEADOW_EDGE_X)
        ((leaving == 0) & (leaving_cave | entering_cave)).then do
          leaving.set! 1
          iris_out at: [hero.x + 4, hero.y + 4], frames: 24
        end

        ((leaving == 1) & iris_shut?).then do
          leaving.set! 0
          (land.showing == land.map_number(:cave)).then do
            land.show_map :meadow
            hero.move_to Cave::MEADOW_EDGE_X + 8, hero.y
            iris_in frames: 24, dark: 0
          end.else do
            land.show_map :cave
            hero.move_to Cave::CAVE_MOUTH_X - 8, Cave::CAVE_MOUTH_Y
            iris_in frames: 24, radius: Cave::LANTERN_REACH, dark: Cave::CAVE_DARK
          end
        end
      end
    end
  end

  def test_the_block_form_and_normal_ruby_make_the_same_cartridge
    block_form = block_form_cave.build_rom(profile: false, out: nil, err: nil, console: :gba)
    normal_ruby = Cave.build_rom(profile: false, out: nil, err: nil, console: :gba)

    assert_equal block_form.buffer.bytes, normal_ruby.buffer.bytes
  end
end
