# frozen_string_literal: true

require "test_helper"
require "tempfile"

# Every kind of write under every kind of test, with Ruby as the answer key. Each game below is
# one source text. It runs as a game, where `hp` is a variable and the test is one the game makes,
# and it runs as plain Ruby, with nothing of VBlank in it. The two must agree, on both sides of
# the test. Written out by hand this would be hundreds of tests, and the kinds nobody thought to
# write are where the silent wrong answers were. It plays on the interpreter alone, since a build
# of each game for each lowering would take far longer than the rewrite it is here to check.
class TestPlainRubyWrites < Minitest::Test
  # A game's source is read back from its file, so each is written to one, and a test that writes
  # files and sets a global is not one a worker Ractor can play.
  runs_on_the_main_ractor!

  Box = Struct.new(:x)

  # Enough of a game for the same text to run as plain Ruby.
  class PlainRubyPlayer
    def var(_name, value) = value
    def game_loop = yield
    def halt = nil
  end

  # Before the test, the write itself, and how the result is read as a number.
  WRITES = {
    "=" => ["x = 1", "x = 2", "x"],
    "+=" => ["x = 1", "x += 1", "x"],
    "||=" => ["x = nil", "x ||= 2", "x ? x : 0"],
    "&&=" => ["x = 1", "x &&= 2", "x"],
    "a, b =" => ["a = 1\n  b = 1", "a, b = 2, 3", "a + b"],
    "@x =" => ["@x = 1", "@x = 2", "@x"],
    "@x +=" => ["@x = 1", "@x += 1", "@x"],
    "h[] =" => ["h = { x: 1 }", "h[:x] = 2", "h[:x]"],
    "h[] +=" => ["h = { x: 1 }", "h[:x] += 1", "h[:x]"],
    "o.x =" => ["o = TestPlainRubyWrites::Box.new(1)", "o.x = 2", "o.x"],
    "o.x +=" => ["o = TestPlainRubyWrites::Box.new(1)", "o.x += 1", "o.x"]
  }.freeze

  FORMS = {
    "if" => "if hp > 3\n    WRITE\n  end",
    "trailing if" => "WRITE if hp > 3",
    "unless" => "unless hp > 3\n    WRITE\n  end",
    "if else" => "if hp > 3\n    WRITE\n  else\n    hp\n  end",
    "elsif" => "if hp > 9\n    hp\n  elsif hp > 3\n    WRITE\n  end",
    "ternary" => "hp > 3 ? (WRITE) : nil",
    "while" => "while hp > 3\n    WRITE\n    hp = 0\n  end",
    "until" => "until hp < 3\n    WRITE\n    hp = 0\n  end",
    "&&" => "hp > 3 && (WRITE)",
    "||" => "hp > 3 || (WRITE)",
    "and if" => "if hp > 3 && hp < 9\n    WRITE\n  end",
    "case" => "case hp\n  when 5 then WRITE\n  end"
  }.freeze

  private def source_of(write, form, start)
    before, written, read = WRITES.fetch(write)
    <<~RUBY
      proc do
        hp = var :hp, #{start}
        #{before}
        #{FORMS.fetch(form).gsub('WRITE', written)}
        shown = 0
        game_loop do
          shown = #{read}
          halt
        end
        #{read}
      end
    RUBY
  end

  private def block_from(source)
    Tempfile.create(["write_table", ".rb"]) do |file|
      file.write("TestPlainRubyWrites::Loaded.block = #{source}")
      file.flush
      load file.path
      yield Loaded.block
    end
  end

  module Loaded
    class << self
      attr_accessor :block
    end
  end

  private def game_answer(source)
    block_from(source) do |block|
      builder = Builder.new
      builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(block, checked: false))
      builder.finalize_program
      Reference.new.run(builder.program, frames: 1)[:shown]
    end
  rescue VBlank::BuildError => e
    :"refused: #{e.message[0, 60]}"
  end

  private def ruby_answer(source)
    block_from(source) do |block|
      answer = PlainRubyPlayer.new.instance_exec(&block)
      answer
    end
  end

  def test_every_write_under_every_test_agrees_with_ruby
    wrong = WRITES.keys.product(FORMS.keys, [1, 5]).filter_map do |write, form, start|
      source = source_of(write, form, start)
      ruby = ruby_answer(source)
      game = game_answer(source)
      "#{write} under #{form}, hp #{start}: Ruby #{ruby.inspect}, game #{game.inspect}" unless ruby == game
    end

    assert_empty wrong, wrong.join("\n")
  end

  def test_a_plain_number_kept_in_a_place_costs_nothing_with_no_game_test
    block_from(source_of("@x =", "if", 5).sub("var :hp, 5", "5")) do |block|
      builder = Builder.new
      builder.instance_eval(&VBlank::DSL::PlainRuby.rewrite(block, checked: false))
      builder.finalize_program

      assert_empty builder.hidden_variable_notes
    end
  end
end
