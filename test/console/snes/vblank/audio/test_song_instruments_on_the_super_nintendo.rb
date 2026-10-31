# frozen_string_literal: true

require "test_helper"
require "song_instrument_tests"

# A song part that plays a recorded instrument, played as the Super Nintendo: its sound unit plays
# each note on a voice of its own, and the mixer's places are counted as the interpreter counts
# them. The tests themselves are in test/song_instrument_tests.rb.
class TestSongInstrumentsOnTheSuperNintendo < Minitest::Test
  include SongInstrumentsTests
end
