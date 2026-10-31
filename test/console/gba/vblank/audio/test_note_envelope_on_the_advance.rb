# frozen_string_literal: true

require "test_helper"
require "note_envelope_tests"

# The tests of test_note_envelope.rb whose games play their notes from a recording, which a Game Boy
# Color's sound hardware cannot play, played as the Advance; the tests themselves are in
# test/note_envelope_tests.rb.
class TestNoteEnvelopeOnTheAdvance < Minitest::Test
  include NoteEnvelopeVoiceTests
end
