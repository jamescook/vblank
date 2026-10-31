# frozen_string_literal: true

module VBlank
  module DSL
    module PlainRuby
      # What each local name in a game block is: found by reading the whole block first, since
      # `hp = 5` can only be understood from what the lines after it do to `hp`.
      #
      # A name is a GAME VARIABLE if it is given a number and also changed in game code, or was
      # made directly by `var`. Everything else is left as Ruby: a number nothing changes
      # stays a plain number and costs nothing, and `target = hero_x` is a second name.
      class LocalNames
        # The verbs whose blocks hold code the game runs as it plays. A plain Ruby block, like
        # the one given to `8.times`, runs while building however it is nested.
        GAME_VERBS = %i[game_loop scene func each_pass every after repeat once_a_frame on_tick item].freeze

        ARITHMETIC = %i[+ - * / % << >> -@ abs].freeze

        # How Ruby goes over a list or a count. Called on something written out in the source, a
        # constant or a literal or a range, it runs here and now however deep in game code it
        # sits: `MELODY.each { cursor += dur }` in a game loop is adding up while building. On
        # a name it cannot be told from a pool's `each`, so that counts as game code.
        RUBY_ITERATORS = %i[downto each each_index each_slice each_with_index each_with_object flat_map map select
                            step times upto].freeze

        Write = Struct.new(:node, :in_game_code)

        CHANGES = [Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
                   Prism::LocalVariableTargetNode].freeze

        # What gives a name a value outright, one name of `a, b = 1, 2` among them.
        WHOLE_WRITES = [Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode].freeze

        # Writes by game code to a local of the scope the block sits in.
        attr_reader :outside_writes

        # One local, in the scope that owns it.
        class Local
          attr_reader :name, :writes, :reads
          attr_accessor :variable_name

          def initialize(name, parameter:)
            @name = name
            @parameter = parameter
            @writes = []
            @reads = []
          end

          def read_from?(offset) = reads.any? { |read| read.location.start_offset >= offset }

          def parameter? = @parameter
          def first_write = @writes.first
          def first_write_of?(node) = first_write.node.equal?(node)

          def made_by_var? = !first_write.nil? && LocalNames.var_call?(first_write.node)

          def auto_variable?
            return false if parameter? || !starts_variable?

            @writes.drop(1).any?(&:in_game_code)
          end

          # In setting up, whatever a name is given is looked at as the line runs, so any start
          # will do. In game code a worked-out start stays a working-out, which Ruby's arithmetic
          # carries down the lines and which costs no memory.
          def starts_variable?
            return true if LocalNames.starts_from_value?(first_write.node)

            WHOLE_WRITES.any? { |kind| first_write.node.is_a?(kind) } && !first_write.in_game_code
          end

          def plain_name? = parameter? || !variable?

          def variable? = auto_variable? || made_by_var?
        end

        def self.var_call?(write)
          return false unless write.respond_to?(:value)

          value = write.value
          value.is_a?(Prism::CallNode) && %i[var save_var].include?(value.name) && value.receiver.nil?
        end

        # `var :x, 0`, on anything: a part of a game is handed the builder and calls `build.var`.
        def self.makes_variable?(value) = value.is_a?(Prism::CallNode) && %i[var save_var].include?(value.name)

        def self.number?(write)
          write.is_a?(Prism::LocalVariableWriteNode) &&
            [Prism::IntegerNode, Prism::FloatNode, Prism::TrueNode, Prism::FalseNode, Prism::SymbolNode].include?(write.value.class)
        end

        # A number written out, or something only running the line can say is one: `state = PLAYING`,
        # `x = WIDTH / 2`. See Rewriter#declaration.
        def self.starts_from_value?(write)
          number?(write) || (write.is_a?(Prism::LocalVariableWriteNode) && made_of_constants?(write.value))
        end

        def self.made_of_constants?(node)
          case node
          when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::IntegerNode, Prism::FloatNode then true
          when Prism::ParenthesesNode then made_of_constants?(node.body.body.first)
          when Prism::CallNode
            ARITHMETIC.include?(node.name) && made_of_constants?(node.receiver) &&
              node.arguments&.arguments.to_a.all? { |each_argument| made_of_constants?(each_argument) }
          else false
          end
        end

        def initialize(block_node)
          @locals_by_node = {}.compare_by_identity
          @ruby_iteration_writes = {}.compare_by_identity
          @outside_writes = []
          @promoted_writes = {}.compare_by_identity
          @names_used = Hash.new(0)
          @iterating_in_game_code = false
          read_names(block_node, [], false)
        end

        # What a rewritten `x = ...` does: nil to leave it, :declare for the line that makes a
        # variable while setting up, :start for one that makes it in game code and so sets it
        # every pass, :assign to change the variable. A method's argument is its own value, as in
        # Ruby, so a write to one changes nothing the caller holds.
        def action_for(write)
          local = @locals_by_node[write]
          return if local.nil? || local.parameter?
          return first_write_action(local) if local.first_write_of?(write)
          return unless local.variable?

          LocalNames.var_call?(write) ? nil : :assign
        end

        # Does this write only change what a name holds, as any Ruby name does?
        def plain_name_write?(write) = @locals_by_node[write]&.plain_name? || false

        def variable_name_of(write)
          local = @locals_by_node.fetch(write)
          local.variable_name ||= next_variable_name(local.name)
        end

        # The plain names +sides+ change that are read after +node+, in a conditional or a loop that
        # may turn out to be a test the game makes. A name read nowhere else needs nothing. It
        # stops at a block, whose writes are not in the same scope as the test.
        def names_to_promote(node, sides)
          writes = sides.compact.flat_map { |side| plain_writes_in(side) }
          kept = writes.select { |write| @locals_by_node[write].read_from?(node.location.end_offset) }
          kept.each { |write| @promoted_writes[write] = true }
          kept.map(&:name).uniq
        end

        # Is this a write to a name that #names_to_promote named?
        def promoted?(write) = @promoted_writes.key?(write)

        # Is this write a number, staying plain, being changed from a block inside its scope?
        def plain_number_changed_from_block?(write)
          local = @locals_by_node[write]
          return false unless local && write.depth.positive? && !local.variable?
          return false if @ruby_iteration_writes.key?(write)

          LocalNames.number?(local.first_write.node)
        end

        # Is this write's name a game variable?
        def variable_write?(write) = @locals_by_node[write]&.variable? || false

        # Is this read of a local a read of a game variable?
        def variable_read?(read) = @locals_by_node[read]&.variable? || false

        private

        def plain_writes_in(node)
          return [] if [Prism::BlockNode, Prism::LambdaNode, Prism::DefNode].any? { |kind| node.is_a?(kind) }

          own = plain_name_write?(node) && CHANGES.any? { |kind| node.is_a?(kind) } ? [node] : []
          own + node.compact_child_nodes.flat_map { |child| plain_writes_in(child) }
        end

        def first_write_action(local)
          return if local.made_by_var? || !local.auto_variable?

          local.first_write.in_game_code ? :start : :declare
        end

        def next_variable_name(name)
          used = @names_used[name] += 1
          used == 1 ? name : :"#{name}_#{used}"
        end

        def read_names(node, scopes, in_game_code)
          case node
          when Prism::BlockNode, Prism::LambdaNode then read_block(node, scopes, in_game_code)
          when Prism::DefNode then read_block(node, [], false)
          when Prism::CallNode then read_call(node, scopes, in_game_code)
          when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode
            read_children(node, scopes, in_game_code || @iterating_in_game_code)
          when Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
               Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode,
               Prism::LocalVariableTargetNode then
            record_write(node, scopes, in_game_code)
            read_children(node, scopes, in_game_code)
          when Prism::LocalVariableReadNode then
            local = scopes[-1 - node.depth]&.[](node.name)
            local&.reads&.push(node)
            @locals_by_node[node] = local if local
          else read_children(node, scopes, in_game_code)
          end
        end

        def read_children(node, scopes, in_game_code)
          node.compact_child_nodes.each { |child| read_names(child, scopes, in_game_code) }
        end

        def read_call(node, scopes, in_game_code)
          node.compact_child_nodes.each do |child|
            next read_ruby_iteration(child, scopes, in_game_code) if child.is_a?(Prism::BlockNode) && ruby_iteration?(node)

            game_block = child.is_a?(Prism::BlockNode) && GAME_VERBS.include?(node.name)
            read_names(child, scopes, in_game_code || game_block)
          end
        end

        def ruby_iteration?(call) = RUBY_ITERATORS.include?(call.name) && written_out?(call.receiver)

        # Is this a constant, a number, a list or a range in the source, or a call on one?
        def written_out?(node)
          case node
          when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ArrayNode, Prism::RangeNode,
               Prism::IntegerNode then true
          when Prism::ParenthesesNode then written_out?(node.body.body.first)
          when Prism::CallNode then !node.receiver.nil? && written_out?(node.receiver)
          else false
          end
        end

        # A test inside it can still be one the game makes, so what is under a conditional there
        # stays game code. See the IfNode line in #read.
        def read_ruby_iteration(block, scopes, in_game_code)
          outer = @iterating_in_game_code
          @iterating_in_game_code = outer || in_game_code
          read_names(block, scopes, false)
        ensure
          @iterating_in_game_code = outer
        end

        def read_block(node, scopes, in_game_code)
          scope = {}
          parameter_names(node.parameters).each { |name| scope[name] = Local.new(name, parameter: true) }
          read_children(node, scopes + [scope], in_game_code)
        end

        def parameter_names(node)
          return [] unless node

          own = node.respond_to?(:name) && node.name ? [node.name] : []
          own + node.compact_child_nodes.flat_map { |child| parameter_names(child) }
        end

        def record_write(node, scopes, in_game_code)
          scope = scopes[-1 - node.depth]
          @outside_writes << node if scope.nil? && in_game_code
          return unless scope

          local = (scope[node.name] ||= Local.new(node.name, parameter: false))
          local.writes << Write.new(node, in_game_code)
          local.reads << node unless WHOLE_WRITES.any? { |kind| node.is_a?(kind) }
          @ruby_iteration_writes[node] = true if @iterating_in_game_code && !in_game_code
          @locals_by_node[node] = local
        end
      end
    end
  end
end
