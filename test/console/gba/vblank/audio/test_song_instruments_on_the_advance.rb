# frozen_string_literal: true

require "test_helper"
require "song_instrument_tests"

# THE TESTS OF vblank/audio/test_song_instruments.rb THAT THE GAME BOY COLOR CANNOT PLAY, played as the
# Advance; the rest are in that file, and the tests themselves in test/song_instrument_tests.rb.
class TestSongInstrumentsOnTheAdvance < Minitest::Test
  include SongInstrumentsTests
end
