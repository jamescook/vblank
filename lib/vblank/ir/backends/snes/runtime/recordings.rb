# frozen_string_literal: true

module VBlank
  module IR
    module Backends
      class SNES
        module Runtime
          # THE GAME'S OWN RECORDINGS (`play_sample`, `stop_sample`).
          #
          # The Advance's processor adds every recording a game plays into one stream, sixteen of them
          # at most, and the interpreter does the same sums (Reference::Mixer). The S-DSP needs none of
          # that: each recording plays on a voice of its own, read from the sound unit's memory
          # (Samples.recording). Four of its voices are free beside the four the Advance's own voices
          # take, so the first four of the sixteen places play there — voice 4 for the first, 7 for the
          # fourth — and a recording in a later place is counted and not heard.
          #
          # THE COUNT IS THE INTERPRETER'S. What the game can tell of a recording — the log saying it
          # came round again, its place coming free at its end — follows where it has got to, so each
          # place keeps that as the interpreter's mixer does: how far into the recording, in whole
          # samples and 65536ths, moved on once a frame by the samples a frame reads
          # (Console::SampleClock.on_voices), read back by its loop at its end, or freed.
          #
          # Each play the game writes is a row of the table "recording_plays" (Lowering::Sound): the
          # voice's source number, pitch and volume, the recording's length, how far back it reads at
          # its end (nought for one played once), how far it moves a frame, the number of its entry in
          # the sound log ([:sample, name]) and which recording it is.
          #
          # A SONG'S RECORDED PART plays its notes in the same places (rt_recordings_note), taking one
          # by the interpreter's rule (Reference::Mixer#start_music_note): the part's own, while it
          # still sounds a note; the first free; or the place of the lowest-ranked sound ranked below
          # the song — the game's own first, of those one that plays once before one that loops, and
          # the oldest. With none, the note is not played. A rest gives the part's place back
          # (rt_recordings_note_release), and so does the tune stopping (rt_recordings_release_music).
          module Recordings
            PLACES = Console::SUPER_NINTENDO.recordings_at_once
            VOICES_HEARD = 4
            FIRST_VOICE = DSPWrites::FIRST_RECORDING_VOICE

            # A play's row in the table, in bytes.
            SOURCE = 0
            PITCH = 2
            VOLUME = 4
            LENGTH = 6
            BACK = 10
            ADVANCE = 14
            ADVANCE_FRACTION = 18
            LOGGED = 20
            NAME = 22
            ROW_BYTES = 32

            # A place's state, PLACE_BYTES apart: which recording (its number plus one, nought when the
            # place is free), how far into it (whole samples, two words, and the fraction), and the
            # play's length, read-back, how far a frame and log entry, copied from its row.
            PLACES_STATE = "rt recordings places"
            HELD = 0
            POSITION = 2
            FRACTION = 6
            PLACE_LENGTH = 8
            PLACE_BACK = 12
            PLACE_ADVANCE = 16
            PLACE_ADVANCE_FRACTION = 20
            PLACE_LOGGED = 22
            # ...and whose it is: nought for the game's own, a part's OWNER number for a song's; the
            # rank it holds the place at, the song's rank's place one up (nought for the game's own,
            # which rank below every song); and for the game's own, its TICKET — LOOPS set for one that
            # loops, and how many the game had started before it — which orders who gives way first.
            OWNER = 24
            RANK = 26
            TICKET = 28
            PLACE_BYTES = 32
            LOOPS = 0x8000
            # A row's LOGGED for a note of a song: nothing is logged as it comes round again.
            NOT_LOGGED = 0xFFFF
            # ...and, for each of the last Frame::STEPS_KEPT passes, by the pass's number less its
            # multiples of STEPS_KEPT, each place's recording as its wait ended: a byte a place.
            KEPT_BY_PASS = "rt recordings kept by pass"

            # Where the row being played is, the place it takes, that place's voice's first register,
            # and which recording a stop names (or ALL) and its entry in the log.
            ROW = "rt recordings row"
            PLACE = "rt recordings place"
            REGISTERS = "rt recordings registers"
            STOP_NAME = "rt recordings stop name"
            STOP_LOGGED = "rt recordings stop logged"
            # How many of its own sounds the game has started (TICKET), and, while a note finds a place,
            # whose it is, its rank, and the best place found to take and its rank and ticket.
            TICKETS = "rt recordings tickets"
            NOTE_OWNER = "rt recordings note owner"
            NOTE_RANK = "rt recordings note rank"
            BEST = "rt recordings best"
            BEST_RANK = "rt recordings best rank"
            BEST_TICKET = "rt recordings best ticket"
            ALL = 0xFFFF

            module_function

            # A play's row of "recording_plays", as words: its voice's +source+, +pitch+ and +volume+;
            # the recording's +length+ and the +back+ it reads at its end (32 bits each); the +advance+
            # a frame, in samples and 65536ths (48 bits, of which the whole samples take 32); the
            # number of its +logged+ entry; and the +name+'s number.
            def row(source:, pitch:, volume:, length:, back:, advance:, logged:, name:)
              words = Array.new(ROW_BYTES / 2, 0)
              { SOURCE => source, PITCH => pitch, VOLUME => volume, LENGTH => length & 0xFFFF, LENGTH + 2 => length >> 16,
                BACK => back & 0xFFFF, BACK + 2 => back >> 16, ADVANCE => (advance >> 16) & 0xFFFF,
                ADVANCE + 2 => advance >> 32, ADVANCE_FRACTION => advance & 0xFFFF, LOGGED => logged,
                NAME => name }.each { |at, value| words[at / 2] = value }
              words
            end

            def reserve(memory)
              [ROW, PLACE, REGISTERS, STOP_NAME, STOP_LOGGED, TICKETS, NOTE_OWNER, NOTE_RANK, BEST, BEST_RANK,
               BEST_TICKET].each { |name| memory.reserve(name, 2) }
              memory.reserve(PLACES_STATE, PLACES * PLACE_BYTES)
              memory.reserve(KEPT_BY_PASS, Frame::STEPS_KEPT * PLACES)
            end

            def emit(asm, memory)
              at = ->(name, plus = 0) { asm.abs(memory[name], plus) }
              emit_play(asm, at, memory)
              emit_note(asm, at, memory)
              emit_note_release(asm, at, memory)
              emit_stop(asm, at, memory)
              emit_frame(asm, at, memory)
              emit_kept_for_pass(asm, memory)
            end

            # rt_recordings_kept_for_pass: which recording each place holds (its byte of HELD) copied
            # into KEPT_BY_PASS for the pass whose wait is ending, for a reader of the run to hold to
            # the interpreter's mix at that pass's frame boundary (Sound's rt_sound_frame).
            def emit_kept_for_pass(asm, memory)
              asm.label("rt_recordings_kept_for_pass")
              asm.lda(asm.abs(memory[Frame::PASSES]))
              asm.and_a(Frame::STEPS_KEPT - 1)
              Music.emit_times(asm, PLACES)
              asm.tax
              asm.sep(0x20)
              PLACES.times do |place|
                asm.lda(asm.abs(memory[PLACES_STATE], (place * PLACE_BYTES) + HELD))
                asm.sta(asm.abs_x(memory[KEPT_BY_PASS], place))
              end
              asm.rep(0x20)
              asm.rts
            end

            # rt_recordings_play(row): the play's entry logged, and the recording in the first free
            # place from its start (Reference::Mixer#start); with none free, nothing more. In one of
            # the first four places it starts on that place's voice.
            def emit_play(asm, at, memory)
              place = place_field(asm, memory)
              row = ->(field) { asm.long_x("recording_plays", field) }
              asm.label("rt_recordings_play")
              asm.lda(asm.direct(Sound::R0))
              Music.emit_times(asm, ROW_BYTES)
              asm.sta(at.call(ROW))
              asm.tax
              asm.lda(row.call(LOGGED))
              asm.sta(asm.direct(Sound::R0))
              asm.jsl(asm.long("rt_sound_log"))
              asm.ldy(0)
              asm.label("rt_recordings_play_find")
              asm.lda(place.call(HELD))
              asm.beq("rt_recordings_play_found")
              asm.tya
              asm.clc
              asm.adc(PLACE_BYTES)
              asm.tay
              asm.cpy(PLACES * PLACE_BYTES)
              asm.bcc("rt_recordings_play_find")
              asm.rtl # every place busy: dropped, as the mixer drops it
              asm.label("rt_recordings_play_found")
              asm.lda(0) # the game's own, below every song, with the next ticket
              asm.sta(place.call(OWNER))
              asm.sta(place.call(RANK))
              asm.inc(at.call(TICKETS))
              asm.lda(at.call(TICKETS))
              asm.and_a(LOOPS - 1)
              asm.ldx(at.call(ROW))
              asm.sta(place.call(TICKET))
              asm.lda(row.call(BACK))
              asm.ora(row.call(BACK + 2))
              asm.beq("rt_recordings_take")
              asm.lda(place.call(TICKET))
              asm.ora(LOOPS)
              asm.sta(place.call(TICKET))

              # rt_recordings_take: the row at ROW into the place Y holds, from the recording's start,
              # on its voice for one of the first four places. A = 1 after.
              asm.label("rt_recordings_take")
              asm.sty(at.call(PLACE))
              asm.ldx(at.call(ROW))
              asm.lda(row.call(NAME))
              asm.inc
              asm.sta(place.call(HELD))
              asm.lda(0)
              [POSITION, POSITION + 2, FRACTION].each { |field| asm.sta(place.call(field)) }
              { LENGTH => PLACE_LENGTH, LENGTH + 2 => PLACE_LENGTH + 2, BACK => PLACE_BACK, BACK + 2 => PLACE_BACK + 2,
                ADVANCE => PLACE_ADVANCE, ADVANCE + 2 => PLACE_ADVANCE + 2, ADVANCE_FRACTION => PLACE_ADVANCE_FRACTION,
                LOGGED => PLACE_LOGGED }.each do |from, to|
                asm.lda(row.call(from))
                asm.sta(place.call(to))
              end
              # Its voice, for one of the first four places: the voice's registers, and key-on last.
              asm.lda(at.call(PLACE))
              asm.cmp(VOICES_HEARD * PLACE_BYTES)
              asm.bcc("rt_recordings_play_heard")
              asm.lda(1)
              asm.rtl
              asm.label("rt_recordings_play_heard")
              emit_registers(asm, at)
              dsp = DSPWrites
              { dsp::VOLUME_LEFT => VOLUME, dsp::VOLUME_RIGHT => VOLUME, dsp::PITCH_LOW => PITCH,
                dsp::SOURCE => SOURCE }.each do |register, field|
                emit_voice_write(asm, at, register) do
                  asm.ldx(at.call(ROW))
                  asm.lda(row.call(field))
                end
              end
              emit_voice_write(asm, at, dsp::PITCH_HIGH) do
                asm.ldx(at.call(ROW))
                asm.lda(row.call(PITCH))
                asm.xba
              end
              emit_voice_write(asm, at, dsp::ADSR1) { asm.lda(dsp::ADSR_OFF) }
              emit_voice_write(asm, at, dsp::GAIN) { asm.lda(dsp::FIXED_TOP) }
              emit_voice_bit(asm, at)
              asm.sta(asm.direct(Sound::R0))
              asm.stz(asm.direct(Sound::R1))
              asm.jsl(asm.long("rt_sound_key_off_bits")) # its key-off cleared...
              emit_voice_bit(asm, at)
              asm.sta(asm.direct(Sound::R1))
              asm.lda(dsp::KEY_ON)
              asm.sta(asm.direct(Sound::R0))
              asm.jsl(asm.long("rt_sound_write")) # ...then key-on
              asm.lda(1)
              asm.rtl
            end

            # rt_recordings_note(row, owner, rank): a note of a song's recorded part, the row's recording
            # played in a place found by the interpreter's rule (Reference::Mixer#start_music_note): the
            # part's own (+owner+'s), the first free, or the place of the lowest-ranked sound ranked
            # below +rank+ — by its rank, then its ticket, the first of two alike. A = 1 when it found
            # one, nought when the note is not played.
            def emit_note(asm, at, memory)
              place = place_field(asm, memory)
              asm.label("rt_recordings_note")
              asm.lda(asm.direct(Sound::R0))
              Music.emit_times(asm, ROW_BYTES)
              asm.sta(at.call(ROW))
              asm.lda(asm.direct(Sound::R1))
              asm.sta(at.call(NOTE_OWNER))
              asm.lda(asm.direct(Sound::R2))
              asm.sta(at.call(NOTE_RANK))
              # The part's own place, still sounding its note.
              each_place(asm, "rt_recordings_note_own") do |next_place|
                asm.lda(place.call(HELD))
                asm.beq(next_place)
                asm.lda(place.call(OWNER))
                asm.cmp(at.call(NOTE_OWNER))
                asm.branch_long(:beq, "rt_recordings_note_found")
              end
              # The first free place.
              each_place(asm, "rt_recordings_note_free") do |next_place|
                asm.lda(place.call(HELD))
                asm.branch_long(:beq, "rt_recordings_note_found")
                asm.bra(next_place)
              end
              # The lowest-ranked place below the note's rank: BEST is the place offset one up, nought
              # while none is found.
              asm.stz(at.call(BEST))
              each_place(asm, "rt_recordings_note_low") do |next_place|
                asm.lda(place.call(RANK))
                asm.cmp(at.call(NOTE_RANK))
                asm.bcs(next_place) # not below the note
                asm.ldx(at.call(BEST))
                asm.beq("rt_recordings_note_low_best")
                asm.cmp(at.call(BEST_RANK))
                asm.bcc("rt_recordings_note_low_best") # ranked lower than the best yet
                asm.bne(next_place)
                asm.lda(place.call(TICKET))
                asm.cmp(at.call(BEST_TICKET))
                asm.bcs(next_place) # no older, or the same: the first stays
                asm.label("rt_recordings_note_low_best")
                asm.lda(place.call(RANK))
                asm.sta(at.call(BEST_RANK))
                asm.lda(place.call(TICKET))
                asm.sta(at.call(BEST_TICKET))
                asm.tya
                asm.inc
                asm.sta(at.call(BEST))
              end
              asm.lda(at.call(BEST))
              asm.bne("rt_recordings_note_lowest")
              asm.rtl # none: the note is not played, and A is nought
              asm.label("rt_recordings_note_lowest")
              asm.dec
              asm.tay
              asm.label("rt_recordings_note_found")
              asm.lda(at.call(NOTE_OWNER))
              asm.sta(place.call(OWNER))
              asm.lda(at.call(NOTE_RANK))
              asm.sta(place.call(RANK))
              asm.lda(0)
              asm.sta(place.call(TICKET))
              asm.jmp(asm.abs("rt_recordings_take"))
            end

            # rt_recordings_note_release(owner): the place +owner+'s part sounds a note in, if it has
            # one, freed and its voice let go (Reference::Mixer#release_music).
            # rt_recordings_release_music: every place a song's part holds freed so
            # (Reference::Mixer#release_all_music).
            def emit_note_release(asm, at, memory)
              place = place_field(asm, memory)
              asm.label("rt_recordings_note_release")
              asm.lda(asm.direct(Sound::R0))
              asm.sta(at.call(NOTE_OWNER))
              each_place(asm, "rt_recordings_note_release") do |next_place|
                asm.lda(place.call(HELD))
                asm.beq(next_place)
                asm.lda(place.call(OWNER))
                asm.cmp(at.call(NOTE_OWNER))
                asm.bne(next_place)
                asm.jsr(asm.abs("rt_recordings_free"))
              end
              asm.rtl

              asm.label("rt_recordings_release_music")
              each_place(asm, "rt_recordings_release_music") do |next_place|
                asm.lda(place.call(HELD))
                asm.beq(next_place)
                asm.lda(place.call(OWNER))
                asm.beq(next_place) # the game's own
                asm.jsr(asm.abs("rt_recordings_free"))
              end
              asm.rtl

              # rt_recordings_free: the place Y holds freed, and its voice let go if it is heard. Keeps Y.
              asm.label("rt_recordings_free")
              asm.lda(0)
              asm.sta(place.call(HELD))
              asm.sty(at.call(PLACE))
              asm.cpy(VOICES_HEARD * PLACE_BYTES)
              asm.bcs("rt_recordings_free_done")
              emit_voice_bit(asm, at)
              asm.sta(asm.direct(Sound::R0))
              asm.sta(asm.direct(Sound::R1))
              asm.phy
              asm.jsl(asm.long("rt_sound_key_off_bits"))
              asm.ply
              asm.label("rt_recordings_free_done")
              asm.rts
            end

            # A walk over every place, Y each one's offset: the block's code for each, given the label
            # that goes on to the next.
            def each_place(asm, label)
              asm.ldy(0)
              asm.label("#{label}_place")
              yield "#{label}_next"
              asm.label("#{label}_next")
              asm.tya
              asm.clc
              asm.adc(PLACE_BYTES)
              asm.tay
              asm.cpy(PLACES * PLACE_BYTES)
              asm.branch_long(:bcc, "#{label}_place")
            end

            # rt_recordings_stop(name, logged): every place playing recording +name+ (or every place,
            # for ALL) freed, a heard one's voice let go, and [:stop_sample] logged (Reference::Mixer#stop).
            def emit_stop(asm, at, memory)
              place = place_field(asm, memory)
              asm.label("rt_recordings_stop")
              asm.lda(asm.direct(Sound::R0))
              asm.sta(at.call(STOP_NAME))
              asm.lda(asm.direct(Sound::R1))
              asm.sta(at.call(STOP_LOGGED))
              asm.stz(at.call(PLACE))
              asm.label("rt_recordings_stop_next")
              asm.ldy(at.call(PLACE))
              asm.lda(place.call(HELD))
              asm.beq("rt_recordings_stop_walk")
              asm.dec
              asm.ldx(at.call(STOP_NAME))
              asm.cpx(ALL)
              asm.beq("rt_recordings_stop_it")
              asm.cmp(at.call(STOP_NAME))
              asm.bne("rt_recordings_stop_walk")
              asm.label("rt_recordings_stop_it")
              asm.lda(0)
              asm.sta(place.call(HELD))
              asm.tya
              asm.cmp(VOICES_HEARD * PLACE_BYTES)
              asm.bcs("rt_recordings_stop_walk")
              emit_voice_bit(asm, at)
              asm.sta(asm.direct(Sound::R0))
              asm.sta(asm.direct(Sound::R1))
              asm.jsl(asm.long("rt_sound_key_off_bits"))
              asm.label("rt_recordings_stop_walk")
              asm.lda(at.call(PLACE))
              asm.clc
              asm.adc(PLACE_BYTES)
              asm.sta(at.call(PLACE))
              asm.cmp(PLACES * PLACE_BYTES)
              asm.bcc("rt_recordings_stop_next")
              asm.lda(at.call(STOP_LOGGED))
              asm.sta(asm.direct(Sound::R0))
              asm.jml(asm.long("rt_sound_log"))
            end

            # rt_recordings_frame: each place playing moved on by a frame (Reference::Mixer#mix_voice):
            # the fraction, then the whole samples and what the fraction carried; past the recording's
            # end, back by its read-back as many times as it takes, logging each time round — or, for one
            # played once, the place freed.
            def emit_frame(asm, at, memory)
              place = place_field(asm, memory)
              asm.label("rt_recordings_frame")
              asm.ldy(0)
              asm.label("rt_recordings_frame_place")
              asm.lda(place.call(HELD))
              asm.branch_long(:beq, "rt_recordings_frame_next")
              asm.clc
              asm.lda(place.call(FRACTION))
              asm.adc(place.call(PLACE_ADVANCE_FRACTION))
              asm.sta(place.call(FRACTION))
              asm.lda(place.call(POSITION))
              asm.adc(place.call(PLACE_ADVANCE))
              asm.sta(place.call(POSITION))
              asm.lda(place.call(POSITION + 2))
              asm.adc(place.call(PLACE_ADVANCE + 2))
              asm.sta(place.call(POSITION + 2))
              asm.label("rt_recordings_frame_end")
              asm.lda(place.call(POSITION + 2))
              asm.cmp(place.call(PLACE_LENGTH + 2))
              asm.bcc("rt_recordings_frame_next")
              asm.bne("rt_recordings_frame_past")
              asm.lda(place.call(POSITION))
              asm.cmp(place.call(PLACE_LENGTH))
              asm.bcc("rt_recordings_frame_next")
              asm.label("rt_recordings_frame_past")
              asm.lda(place.call(PLACE_BACK))
              asm.ora(place.call(PLACE_BACK + 2))
              asm.bne("rt_recordings_frame_back")
              asm.sta(place.call(HELD)) # played once, and over: A is nought
              asm.bra("rt_recordings_frame_next")
              asm.label("rt_recordings_frame_back")
              asm.sec
              asm.lda(place.call(POSITION))
              asm.sbc(place.call(PLACE_BACK))
              asm.sta(place.call(POSITION))
              asm.lda(place.call(POSITION + 2))
              asm.sbc(place.call(PLACE_BACK + 2))
              asm.sta(place.call(POSITION + 2))
              asm.lda(place.call(PLACE_LOGGED))
              asm.cmp(NOT_LOGGED) # a song's note: nothing logged as it comes round
              asm.beq("rt_recordings_frame_end")
              asm.sta(asm.direct(Sound::R0))
              asm.phy
              asm.jsl(asm.long("rt_sound_log"))
              asm.ply
              asm.bra("rt_recordings_frame_end")
              asm.label("rt_recordings_frame_next")
              asm.tya
              asm.clc
              asm.adc(PLACE_BYTES)
              asm.tay
              asm.cpy(PLACES * PLACE_BYTES)
              asm.branch_long(:bcc, "rt_recordings_frame_place")
              asm.rts
            end

            # A field of the place whose offset Y holds, as an operand.
            def place_field(asm, memory) = ->(field) { asm.abs_y(memory[PLACES_STATE], field) }

            # REGISTERS = the first register of the voice of the place at PLACE (one of the first four).
            def emit_registers(asm, at)
              asm.lda(at.call(PLACE))
              (PLACE_BYTES.bit_length - 1).times { asm.lsr } # the place's number: its offset over PLACE_BYTES
              asm.clc
              asm.adc(FIRST_VOICE)
              4.times { asm.asl }
              asm.sta(at.call(REGISTERS))
            end

            # A = the bit of the voice of the place at PLACE, in KON and KOFF.
            def emit_voice_bit(asm, at)
              asm.lda(at.call(PLACE))
              (PLACE_BYTES.bit_length - 1).times { asm.lsr }
              asm.tax
              asm.lda(1 << FIRST_VOICE)
              asm.label(label = "rt_recordings_bit_#{asm.here}")
              asm.cpx(0)
              asm.beq("#{label}_done")
              asm.asl
              asm.dex
              asm.bra(label)
              asm.label("#{label}_done")
            end

            # One write to register +register+ of the voice at REGISTERS, its value from the block (in A).
            def emit_voice_write(asm, at, register)
              yield
              asm.and_a(0xFF)
              asm.sta(asm.direct(Sound::R1))
              asm.lda(at.call(REGISTERS))
              asm.clc
              asm.adc(register)
              asm.sta(asm.direct(Sound::R0))
              asm.jsl(asm.long("rt_sound_write"))
            end
          end
        end
      end
    end
  end
end
