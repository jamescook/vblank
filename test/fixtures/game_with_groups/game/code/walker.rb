# frozen_string_literal: true

require "vblank"

# The game, kept where this game keeps its code rather than under lib/.
module Walker
  GAME = VBlank.game "WALKER", consoles: %i[gba] do
    x = var :x, 0
    game_loop do
      x += 1 if held(:right)
      pixel 10, 10, :red
    end
  end
end
