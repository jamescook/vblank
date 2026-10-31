# frozen_string_literal: true

# Game code, which `require_relative` leaves unread: `state = 1` would set only a Ruby name.
module WalkerSteps
  def walk
    state = var :state, 0
    state = 1
    game_loop { wait_vblank }
    state
  end
end
