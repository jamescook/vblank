# frozen_string_literal: true

# Parts of a game as plain classes holding a builder, brought in by `VBlank.require_game_file` for
# test/all/vblank/dsl/test_plain_ruby_parts.rb. None of them has a `var` of its own.
class CounterPart
  def initialize(builder)
    @builder = builder
    declare
  end

  private

  def declare
    builder = @builder
    count = builder.var(:counter_count, 0)
    builder.func(:counter_tick) { count = count + 1 }
  end
end

class SparklePart
  def initialize(builder)
    @builder = builder
    declare
  end

  private

  def declare
    builder = @builder
    glint = nil
    builder.func(:sparkle_make) do
      glint = builder.var(:sparkle_glint, 0)
      glint = 7
    end
  end
end

class TallyPart
  def initialize(builder)
    @builder = builder
    declare
  end

  private

  def declare
    builder = @builder
    tally = 3
    builder.func(:tally_tick) { tally += 1 }
    builder.func(:tally_show) { builder.var(:tally_seen, 0).store!(tally) }
  end
end

class SeveralOfOnePart
  def initialize(builder, routine)
    ticks = 0
    builder.func(routine) { ticks += 1 }
  end
end

class TwoNamesPart
  def initialize(builder)
    @builder = builder
    declare
  end

  private

  def declare
    builder = @builder
    first, second = builder.var(:unpacked_first, 1), builder.var(:unpacked_second, 2)
    builder.func(:unpacked_tick) do
      first += 1
      second = first
    end
  end
end
