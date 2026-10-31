# frozen_string_literal: true

# Two files of a game, for test/all/vblank/dsl/test_plain_ruby_parts.rb. Each sets a local called
# `speed`, and a file's locals are its own, as they are for `require`. The constant and the method
# from the second file cross over, as they do in Ruby.
speed = 1
VBlank.require_game_file "second"

TWO_PARTS_SPEED = speed
TWO_PARTS_ACROSS = two_parts_doubled(TWO_PARTS_FROM_SECOND)
