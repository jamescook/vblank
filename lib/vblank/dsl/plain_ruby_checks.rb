# frozen_string_literal: true

module VBlank
  module DSL
    module PlainRuby
      # Refuses what a game block cannot use, before any of it runs.
      #
      # NOTHING HERE LISTS WHAT IS BANNED, except a few calls that have no constant to look at.
      # There is no end of gems and libraries, so a name in the block is refused unless it is
      # known to be the game's own, VBlank's, or a harmless piece of Ruby. These checks catch
      # mistakes. They are not a wall: the game's own helper in another file can call anything.
      #
      # THE CALLS ARE CHECKED AS THE GAME IS DECLARED, from the source alone. The constants wait
      # until the game is built, since one defined lower down the author's file is not there
      # yet, so what they need goes into the rewritten block as plain data (see #constant_check).
      class BlockChecks
        # Pieces of Ruby that only work with numbers and lists.
        RUBY_BASICS = %i[Array Comparable Float Hash Integer Math Range Rational String Symbol].freeze

        # What reaches outside the game with no constant to see: Ruby's own short list. These
        # are only Ruby's when nothing stands in front of them. `sparks.spawn` is a game verb
        # and `save.load` another, and neither is Ruby's `spawn` or `load`.
        OUTSIDE_CALLS = %i[abort at_exit binding eval exec exit exit! fork load open require
                           require_relative sleep spawn syscall system trap].freeze

        # ...and what gets round the checks whatever it is called on.
        INDIRECT_CALLS = %i[__send__ class_eval const_get instance_eval public_send send].freeze

        def self.refuse_outside_constant!(constants, nesting:, folder:, allow:, file:)
          library = "#{VBlank.root.join('lib')}/"
          constants.each do |name, line|
            next if RUBY_BASICS.include?(name) || allow.include?(name.to_s)
            next if game_constant?(name, nesting, [folder, library])

            raise Refused, "`#{name}` is not part of your game, so this block cannot use it. This " \
                           "block describes what the game does as it plays. If you need `#{name}` " \
                           "while building, use it above the block and keep the result in a " \
                           "constant. If this library is safe here, add it with `allow:`. " \
                           "(at #{file}:#{line})"
          end
        end

        def self.game_constant?(name, nesting, folders)
          owner = nesting.find { |mod| mod.const_defined?(name, false) } || Object
          return false unless owner.const_defined?(name)

          file, = owner.const_source_location(name)
          !file.nil? && folders.any? { |folder| file.start_with?(folder) }
        end
        private_class_method :game_constant?

        def initialize(block_node, file:, allow:)
          @block_node = block_node
          @file = file
          @allow = allow.map(&:to_s)
        end

        def refuse_outside_calls!(node = @block_node)
          refuse_call!(node)
          node.compact_child_nodes.each { |child| refuse_outside_calls!(child) }
        end

        # The call that refuses this block's outside constants, as Ruby source. It reads
        # Module.nesting where it runs, which is how the block's own scope is known.
        def constant_check
          "::VBlank::DSL::PlainRuby::BlockChecks.refuse_outside_constant!(#{constants_named.inspect}, " \
            "nesting: Module.nesting, folder: #{"#{File.dirname(File.expand_path(@file))}/".inspect}, " \
            "allow: #{@allow.inspect}, file: #{File.basename(@file).inspect})"
        end

        private

        def constants_named(node = @block_node)
          case node
          when Prism::ConstantReadNode then [[node.name, node.location.start_line]]
          when Prism::ConstantPathNode then [[first_name_of(node), node.location.start_line]]
          else node.compact_child_nodes.flat_map { |child| constants_named(child) }
          end
        end

        def first_name_of(path)
          path = path.parent while path.is_a?(Prism::ConstantPathNode) && path.parent
          path.is_a?(Prism::ConstantReadNode) ? path.name : :Object
        end

        def refuse_call!(node)
          case node
          when Prism::XStringNode, Prism::InterpolatedXStringNode then refuse_backticks!(node)
          when Prism::CallNode then refuse_outside_call!(node)
          end
        end

        def refuse_outside_call!(node)
          return unless INDIRECT_CALLS.include?(node.name) || (node.receiver.nil? && OUTSIDE_CALLS.include?(node.name))

          refuse!("`#{node.name}` reaches outside the game, so this block cannot use it. If you need " \
                  "it while building, use it above the block and keep the result in a constant.", node)
        end

        def refuse_backticks!(node)
          refuse!("Backticks run a command outside the game, so this block cannot use them. If you " \
                  "need one while building, use it above the block and keep the result in a constant.", node)
        end

        def refuse!(message, node)
          raise Refused, "#{message} (at #{File.basename(@file)}:#{node.location.start_line})"
        end
      end
    end
  end
end
