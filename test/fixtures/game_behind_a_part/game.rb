# frozen_string_literal: true

VBlank.require_game_file "part"

# A game whose part, read as normal Ruby, brings in game code with `require_relative`.
module GameBehindAPart
  def self.block = proc { game_loop { wait_vblank } }
end
