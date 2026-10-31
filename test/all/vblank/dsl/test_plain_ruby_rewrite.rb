# frozen_string_literal: true

require "test_helper"

# A few sanity checks on what a game block is rewritten into. What a game DOES is checked in
# test_plain_ruby.rb; these look only at the choices a person would want to see made: which
# names become `var`, which stay plain, and that every line keeps its number.
class TestPlainRubyRewrite < Minitest::Test
  private def rewritten(&block) = VBlank::DSL::PlainRuby.rewritten_source(block)

  def test_a_number_changed_in_game_code_is_declared_with_var
    source = rewritten do
      hp = 5
      game_loop { hp -= 1 }
    end

    assert_includes source, "hp = var(:hp, 5)"
  end

  def test_a_number_never_changed_stays_a_plain_number
    source = rewritten do
      speed = 2
      hp = 5
      game_loop { hp -= speed }
    end

    assert_includes source, "speed = 2"
    refute_includes source, ":speed"
  end

  def test_a_number_changed_only_outside_game_code_stays_a_plain_number
    source = rewritten do
      count = 0
      8.times { count += 1 }
      game_loop { pixel count, 0, :red }
    end

    refute_includes source, "var("
  end

  def test_the_same_name_in_two_routines_gets_two_variable_names
    source = rewritten do
      func(:one) { x = 1; x += 1 }
      func(:two) { x = 2; x += 1 }
    end

    assert_includes source, "var(:x, 1)"
    assert_includes source, "var(:x_2, 2)"
  end

  def test_every_line_keeps_its_number
    source = rewritten do
      hp = 5
      if hp > 0
        # a comment
        hp -= 1
      elsif hp < 0
        hp = 2
      else
        hp = 3
      end
      unless hp == 1 then hp = 4 end
      while hp > 9
        hp -= 1
      end
      x = hp > 0 ? 1 : 2
      game_loop { hp += x }
    end

    assert_equal 16, source.count("\n"), source
  end
end
