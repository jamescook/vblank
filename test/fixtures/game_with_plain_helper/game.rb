# frozen_string_literal: true

require_relative "numbers"
require_relative "walker"

# A game that brings its walker in with `require_relative`, for the check that says not to.
module GameWithPlainHelper
  def self.block = proc { game_loop { wait_vblank } }
end
