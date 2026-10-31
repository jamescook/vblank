# frozen_string_literal: true

module VBlank
  module IR
    module Guardrails
      module Checks
        # A `while` in normal Ruby on a test the game makes, with no wait for the next frame
        # anywhere in it. The screen is drawn and the buttons are read between frames, so a loop
        # like that holds the whole game still until its test fails, and if only a button press
        # could make it fail, the game has stopped for good.
        #
        # A loop of a known length is an ordinary way to do work inside a frame, so `repeat` is
        # left alone: only the count such a `while` is given is looked for.
        class LoopNeverWaits
          NAME = :loop_never_waits
          PLAIN_NAME = "a loop with no wait for the next frame"

          # The biggest number the game's arithmetic holds. A `while` has no count of its own,
          # and a loop in the game must be given one.
          MOST_PASSES = 0x7FFF_FFFF

          def detect(program)
            funcs = FrameReach.index_funcs(program)
            program.each.select { |node| open_ended_loop?(node) && !waits?(node, funcs) }.map do |node|
              Finding.new(check: NAME, severity: :warning, message: message, node: node)
            end
          end

          private

          def open_ended_loop?(node)
            node.kind == :repeat && node.count.kind == :int && node.count.value == MOST_PASSES
          end

          def waits?(node, funcs)
            FrameReach.per_frame_statements(node, funcs).any? { |statement| statement.kind == :wait_vblank }
          end

          def message
            "This loop never waits for the next frame. The game does not draw and does not read " \
              "the buttons until the loop ends. To fix this, add `wait_vblank` inside the loop."
          end
        end
      end
    end
  end
end
