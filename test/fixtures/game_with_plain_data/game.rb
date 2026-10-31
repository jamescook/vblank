# frozen_string_literal: true

require_relative "../../../lib/vblank"
require_relative "../game_with_plain_helper/numbers"

# A game whose `require_relative` brings in only plain Ruby, and VBlank itself.
module GameWithPlainData
  def self.block = proc { game_loop { wait_vblank } }
end
