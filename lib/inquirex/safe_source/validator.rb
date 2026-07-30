# frozen_string_literal: true

module Inquirex
  module SafeSource
    # Default-deny AST allowlist for the Inquirex flow DSL.
    #
    # The validator parses the source with Prism and walks it by *recursive
    # descent against an expected shape* rather than by visiting every node and
    # asking "is this one forbidden?". At each position — top-level statement,
    # flow-block statement, step-block statement, argument, keyword value, Hash
    # element — only the handful of node types the real DSL produces there are
    # accepted, and anything else is a violation. A node type nobody thought
    # about is therefore rejected by construction, which is the whole point: a
    # blocklist of forbidden methods would be defeated by the first construct
    # that was overlooked.
    #
    # What that rules out, without needing to name any of it: `system`,
    # backticks and `%x`, `exec`/`spawn`/`fork`, `require`/`load`, `eval` and
    # the `*_eval` family, `send`/`__send__`/`public_send`/`method`, every
    # constant reference other than the `Inquirex` entry point (so no `File`,
    # `IO`, `Dir`, `Kernel`, `ENV`, `ObjectSpace`, `Process`,
    # `Object.const_get`), instance, class and global variables,
    # `def`/`class`/`module`, `begin`/`rescue`, `at_exit`, `BEGIN`/`END`,
    # singleton definitions, `__FILE__`-style magic, assignments, conditionals,
    # loops, string/symbol/regexp interpolation (including inside heredocs),
    # splats and block-pass arguments.
    #
    # Ruby blocks are accepted only where the DSL itself opens a nested scope
    # ({Vocabulary} `block:`), and those blocks are validated statement by
    # statement in turn. Every other block is rejected, which is why `compute`,
    # a block-form `default`, `fallback` and an action's `run` cannot be used in
    # safe mode: a `compute` block is indistinguishable from a payload.
    #
    # @example
    #   Validator.new("Inquirex.define { start :a }").violations # => []
    #   Validator.new("system('id')").violations
    #   # => ["line 1: the DSL must be a single `Inquirex.define` block"]
    class Validator
      # Cap on reported violations, so a hostile 64 KiB payload cannot turn a
      # validation error into a megabyte of flash message.
      MAX_REPORTED = 10

      # Appended to violations an author could legitimately have meant.
      UNSAFE_HINT = " — evaluate source you wrote yourself with `Inquirex.load_dsl(text, unsafe: true)`"

      # Node types worth naming explicitly in a violation message, because the
      # humanized class name would not tell the author what they actually wrote.
      NODE_LABELS = {
        Prism::XStringNode                       => "a backtick or %x command",
        Prism::InterpolatedXStringNode           => "a backtick or %x command",
        Prism::InterpolatedStringNode            => "an interpolated string (interpolation is never allowed, not even in a heredoc)",
        Prism::InterpolatedSymbolNode            => "an interpolated symbol",
        Prism::InterpolatedRegularExpressionNode => "an interpolated regular expression",
        Prism::RegularExpressionNode             => "a regular expression",
        Prism::ConstantReadNode                  => "a constant reference",
        Prism::ConstantPathNode                  => "a constant reference",
        Prism::InstanceVariableReadNode          => "an instance variable",
        Prism::ClassVariableReadNode             => "a class variable",
        Prism::GlobalVariableReadNode            => "a global variable",
        Prism::DefNode                           => "a method definition",
        Prism::ClassNode                         => "a class definition",
        Prism::ModuleNode                        => "a module definition",
        Prism::SingletonClassNode                => "a singleton class definition",
        Prism::BeginNode                         => "a begin/rescue block",
        Prism::LambdaNode                        => "a lambda",
        Prism::BlockNode                         => "a block",
        Prism::BlockArgumentNode                 => "a block-pass (&) argument",
        Prism::SplatNode                         => "a splat (*) argument",
        Prism::AssocSplatNode                    => "a double-splat (**) argument",
        Prism::SourceFileNode                    => "__FILE__",
        Prism::SourceLineNode                    => "__LINE__",
        Prism::SourceEncodingNode                => "__ENCODING__",
        Prism::SelfNode                          => "self",
        Prism::PreExecutionNode                  => "a BEGIN block",
        Prism::PostExecutionNode                 => "an END block"
      }.freeze

      # @param source [String, nil] Inquirex DSL source to validate
      # @param max_bytes [Integer] ceiling on source size
      # @param max_depth [Integer] ceiling on AST nesting depth
      def initialize(source,
        max_bytes: SafeSource::DEFAULT_MAX_SOURCE_BYTES,
        max_depth: SafeSource::DEFAULT_MAX_DEPTH)
        @source = source
        @max_bytes = max_bytes
        @max_depth = max_depth
      end

      # Every reason this source falls outside the allowlist.
      #
      # @return [Array<String>] `"line N: reason"` messages, empty when safe
      def violations
        @violations ||= analyze.uniq.first(MAX_REPORTED)
      end

      private

      # @return [Array<String>]
      def analyze
        @found = []
        return ["the DSL is blank"] if @source.nil? || @source.to_s.strip.empty?
        return ["the DSL must be a String, got #{@source.class}"] unless @source.is_a?(String)

        size = @source.bytesize
        return ["the DSL is #{size} bytes, over the #{@max_bytes}-byte limit"] if size > @max_bytes

        result = Prism.parse(@source)
        return syntax_violations(result) if result.failure?
        # A __END__ data section is inert under eval, but nothing that generates
        # flow DSL emits one, and a payload parked below the marker is exactly
        # the sort of thing a future refactor could start feeding somewhere else.
        return ["line #{result.data_loc.start_line}: the DSL must not have a __END__ data section"] if result.data_loc
        if (comment = foreign_encoding(result))
          return ["the DSL must not declare a source encoding (found #{comment.value.inspect}); write UTF-8"]
        end

        check_program(result.value)
        @found
      end

      # An `# encoding:` magic comment naming anything other than UTF-8 or
      # US-ASCII. Validation and evaluation must agree on where one token ends
      # and the next begins; in encodings whose multi-byte sequences may contain
      # ASCII bytes (Shift_JIS and friends) that agreement depends on both
      # readers applying the same encoding, and the comment is the only lever a
      # payload has over it. Nothing that generates flow DSL emits one.
      #
      # @param result [Prism::ParseResult]
      # @return [Prism::MagicComment, nil]
      def foreign_encoding(result)
        result.magic_comments.find do |comment|
          %w[encoding coding].include?(comment.key.downcase) &&
            !%w[utf-8 utf8 us-ascii ascii binary ascii-8bit].include?(comment.value.downcase)
        end
      end

      # @param result [Prism::ParseResult]
      # @return [Array<String>]
      def syntax_violations(result)
        result.errors.first(MAX_REPORTED).map do |error|
          "line #{error.location.start_line}: syntax error — #{error.message}"
        end
      end

      # Records a violation against a node's line.
      #
      # @param node [Prism::Node, nil]
      # @param message [String]
      # @return [nil]
      def reject(node, message)
        line = node&.location&.start_line || 1
        @found << "line #{line}: #{message}"
        nil
      end

      # The whole program must be exactly one `Inquirex.define` block.
      #
      # @param program [Prism::ProgramNode]
      # @return [void]
      def check_program(program)
        body = program.statements.body
        if body.length != 1
          return reject(program,
            "the DSL must be a single `#{Vocabulary::ENTRY_CONSTANT}.#{Vocabulary::ENTRY_METHOD}` block " \
            "(found #{body.length} top-level statements)")
        end

        check_entry(body.first)
      end

      # @param node [Prism::Node] the single top-level statement
      # @return [void]
      def check_entry(node)
        unless entry_call?(node)
          return reject(node,
            "the DSL must be a single `#{Vocabulary::ENTRY_CONSTANT}.#{Vocabulary::ENTRY_METHOD}` block")
        end

        spec = Vocabulary.entry_spec
        check_block_for(node, spec, depth: 1)
        check_arguments(node, spec, depth: 1)
      end

      # @param node [Prism::Node]
      # @return [Boolean] whether this is literally `Inquirex.define`
      def entry_call?(node)
        node.is_a?(Prism::CallNode) &&
          node.name == Vocabulary::ENTRY_METHOD &&
          !node.safe_navigation? &&
          node.receiver.is_a?(Prism::ConstantReadNode) &&
          node.receiver.name == Vocabulary::ENTRY_CONSTANT
      end

      # Validates every statement in a block body against a scope's table.
      #
      # @param block [Prism::BlockNode]
      # @param scope [Symbol] a scope registered with {Vocabulary.register_scope}
      # @param depth [Integer]
      # @return [void]
      def check_block(block, scope, depth:)
        return reject(block, too_deep_message) if too_deep?(depth)

        reject(block.parameters, "#{scope_label(scope)} block takes no parameters") if block.parameters

        body = block.body
        return if body.nil?
        unless body.is_a?(Prism::StatementsNode)
          return reject(body, "#{describe(body)} is not allowed inside #{scope_label(scope)} block")
        end

        body.body.each { |statement| check_call(statement, scope, depth: depth + 1) }
      end

      # @param node [Prism::Node] one statement from a block body
      # @param scope [Symbol]
      # @param depth [Integer]
      # @return [void]
      def check_call(node, scope, depth:)
        return reject(node, too_deep_message) if too_deep?(depth)

        unless plain_self_call?(node)
          return reject(node, "#{describe(node)} is not allowed inside #{scope_label(scope)} block")
        end

        spec = Vocabulary.spec_for(scope, node.name)
        return reject_unknown_call(node, scope) if spec.nil?

        # Blocks are checked first so that `default { ... }` reports the Ruby
        # block, not the argument count it happens to also get wrong.
        check_block_for(node, spec, depth: depth)
        check_arguments(node, spec, depth: depth)
      end

      # Explains a call the scope's table does not contain — quoting the
      # recorded reason when the word exists but was deliberately excluded.
      #
      # @param node [Prism::CallNode]
      # @param scope [Symbol]
      # @return [nil]
      def reject_unknown_call(node, scope)
        reason = Vocabulary.exclusion_for(scope, node.name)
        return reject(node, "`#{node.name}` is not available in safe mode: #{reason}#{UNSAFE_HINT}") if reason

        reject(node, "`#{node.name}` is not allowed inside #{scope_label(scope)} block")
      end

      # A bare `keyword ...` call on implicit self — no receiver, no `&.`.
      #
      # @param node [Prism::Node]
      # @return [Boolean]
      def plain_self_call?(node)
        node.is_a?(Prism::CallNode) &&
          node.receiver.nil? &&
          !node.safe_navigation? &&
          node.call_operator_loc.nil?
      end

      # @param node [Prism::CallNode]
      # @param spec [CallSpec]
      # @param depth [Integer]
      # @return [void]
      def check_arguments(node, spec, depth:)
        args = node.arguments&.arguments&.dup || []

        # A trailing keyword hash is only peeled off when the call actually
        # takes keywords. For `options single: "Single"` the hash IS the one
        # positional argument, which is exactly how Ruby passes it.
        keywords = args.pop if spec.keywords && args.last.is_a?(Prism::KeywordHashNode)

        check_positional(node, args, spec.positional, depth: depth)
        check_keywords(node, keywords, spec.keywords, depth: depth)
      end

      # @param node [Prism::CallNode] for the error message and line number
      # @param args [Array<Prism::Node>] positional arguments
      # @param descriptor [Array<Symbol>, Hash] see {CallSpec#positional}
      # @param depth [Integer]
      # @return [void]
      def check_positional(node, args, descriptor, depth:)
        case descriptor
        when Array
          if args.length != descriptor.length
            return reject(node, "`#{node.name}` takes #{descriptor.length} argument(s), got #{args.length}")
          end

          descriptor.each_with_index do |kind, index|
            check_value(args[index], kind, depth: depth + 1, context: "`#{node.name}` argument #{index + 1}")
          end
        when Hash
          check_variadic(node, args, descriptor, depth: depth)
        end
      end

      # @param node [Prism::CallNode]
      # @param args [Array<Prism::Node>]
      # @param descriptor [Hash] `{ repeat:, min: }` or `{ optional: }`
      # @param depth [Integer]
      # @return [void]
      def check_variadic(node, args, descriptor, depth:)
        if (kind = descriptor[:repeat])
          minimum = descriptor.fetch(:min, 0)
          return reject(node, "`#{node.name}` needs at least #{minimum} argument(s)") if args.length < minimum
        else
          kind = descriptor.fetch(:optional)
          return reject(node, "`#{node.name}` takes at most 1 argument") if args.length > 1
        end

        args.each_with_index do |arg, index|
          check_value(arg, kind, depth: depth + 1, context: "`#{node.name}` argument #{index + 1}")
        end
      end

      # @param node [Prism::CallNode]
      # @param keywords [Prism::KeywordHashNode, nil]
      # @param descriptor [nil, Hash] see {CallSpec#keywords}
      # @param depth [Integer]
      # @return [void]
      def check_keywords(node, keywords, descriptor, depth:)
        return if keywords.nil?
        return reject(keywords, "`#{node.name}` takes no keyword arguments") if descriptor.nil?

        keywords.elements.each do |element|
          unless element.is_a?(Prism::AssocNode)
            next reject(element, "`#{node.name}`: #{describe(element)} is not allowed in a keyword list")
          end

          name = literal_key(element.key)
          next reject(element.key, "`#{node.name}`: keyword names must be plain symbols") if name.nil?

          kind = descriptor[name] || descriptor[Vocabulary::ANY_OTHER]
          next reject(element, "`#{node.name}` does not accept `#{name}:`") if kind.nil?

          check_value(element.value, kind, depth: depth + 1, context: "`#{node.name}` #{name}:")
        end
      end

      # @param node [Prism::Node, nil]
      # @param kind [Symbol] :literal, :string, :symbol, :type_name or :rule
      # @param depth [Integer]
      # @param context [String] what this value belongs to, for the message
      # @return [void]
      def check_value(node, kind, depth:, context:)
        return reject(node, too_deep_message) if too_deep?(depth)

        case kind
        when :literal   then check_literal(node, depth: depth, context: context)
        when :string    then check_static(node, :static_string?, "a plain string", context: context)
        when :symbol    then check_static(node, :static_symbol?, "a plain symbol", context: context)
        when :type_name then check_type_name(node, context: context)
        when :rule      then check_rule(node, depth: depth, context: context)
        end
      end

      # @param node [Prism::Node, nil]
      # @param predicate [Symbol] {#static_string?} or {#static_symbol?}
      # @param label [String] how to describe the accepted shape to the author
      # @param context [String]
      # @return [void]
      def check_static(node, predicate, label, context:)
        return if send(predicate, node)

        reject(node, "#{context} must be #{label}, found #{describe(node)}")
      end

      # One of the gem's own data types. Bound to {Node::TYPES} rather than
      # accepting any symbol, so a typo is a validation error instead of a step
      # that silently renders as free text.
      #
      # @param node [Prism::Node, nil]
      # @param context [String]
      # @return [void]
      def check_type_name(node, context:)
        return reject(node, "#{context} must be a plain symbol, found #{describe(node)}") unless static_name?(node)
        return if Node::TYPES.include?(node.unescaped.to_sym)

        reject(node, "#{context} must be one of #{Node::TYPES.join(", ")}, found #{node.unescaped}")
      end

      # A string with no embedded expressions.
      #
      # Prism represents a dedented heredoc — and adjacent literal
      # concatenation — as an InterpolatedStringNode whose parts happen to be
      # plain StringNodes. Those are static text, and multi-line `send_email`
      # bodies rely on them, so they are accepted; the moment any part is an
      # embedded expression (or a nested interpolated string) the node is
      # rejected.
      #
      # @param node [Prism::Node, nil]
      # @return [Boolean]
      def static_string?(node)
        case node
        when Prism::StringNode             then true
        when Prism::InterpolatedStringNode then node.parts.all?(Prism::StringNode)
        else false
        end
      end

      # A symbol with no embedded expressions.
      #
      # @param node [Prism::Node, nil]
      # @return [Boolean]
      def static_symbol?(node)
        case node
        when Prism::SymbolNode             then true
        when Prism::InterpolatedSymbolNode then node.parts.all?(Prism::StringNode)
        else false
        end
      end

      # A single-part symbol or string, i.e. a node whose text is knowable
      # without evaluating anything.
      #
      # @param node [Prism::Node, nil]
      # @return [Boolean]
      def static_name?(node)
        node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
      end

      # Literals, and Arrays/Hashes built only out of literals.
      #
      # @param node [Prism::Node, nil]
      # @param depth [Integer]
      # @param context [String]
      # @return [void]
      def check_literal(node, depth:, context:)
        return reject(node, too_deep_message) if too_deep?(depth)

        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::TrueNode, Prism::FalseNode, Prism::NilNode
          nil
        when Prism::ArrayNode
          node.elements.each { |element| check_literal(element, depth: depth + 1, context: context) }
        when Prism::HashNode, Prism::KeywordHashNode
          check_hash_literal(node, depth: depth, context: context)
        else
          return if static_string?(node) || static_symbol?(node)

          reject(node, "#{context} must be a literal value, found #{describe(node)}")
        end
      end

      # @param node [Prism::HashNode, Prism::KeywordHashNode]
      # @param depth [Integer]
      # @param context [String]
      # @return [void]
      def check_hash_literal(node, depth:, context:)
        node.elements.each do |element|
          unless element.is_a?(Prism::AssocNode)
            next reject(element, "#{context}: #{describe(element)} is not allowed in a Hash literal")
          end

          if literal_key(element.key).nil?
            next reject(element.key, "#{context}: Hash keys must be plain symbols or strings")
          end

          check_literal(element.value, depth: depth + 1, context: context)
        end
      end

      # @param node [Prism::Node, nil]
      # @param depth [Integer]
      # @param context [String]
      # @return [void]
      def check_rule(node, depth:, context:)
        return reject(node, too_deep_message) if too_deep?(depth)

        spec = plain_self_call?(node) ? Vocabulary.spec_for(:rule, node.name) : nil
        if spec.nil?
          return reject(node,
            "#{context} must be one of #{Vocabulary.allowed_names(:rule).join(", ")}, found #{describe(node)}")
        end
        return reject(node.block, "rule `#{node.name}` takes no block") if node.block

        check_arguments(node, spec, depth: depth)
      end

      # @param node [Prism::CallNode]
      # @param spec [CallSpec]
      # @param depth [Integer]
      # @return [void]
      def check_block_for(node, spec, depth:)
        block = node.block

        if spec.block == :forbidden
          return if block.nil?

          return reject(block,
            "`#{node.name}` takes no block in safe mode — a Ruby block is arbitrary server-side " \
            "code that cannot be validated#{UNSAFE_HINT}")
        end

        return reject(node, "`#{node.name}` requires a block") if block.nil?
        unless block.is_a?(Prism::BlockNode)
          return reject(block, "`#{node.name}` requires a literal block, found #{describe(block)}")
        end

        check_block(block, spec.block, depth: depth + 1)
      end

      # @param depth [Integer]
      # @return [Boolean]
      def too_deep?(depth)
        depth > @max_depth
      end

      # @return [String]
      def too_deep_message
        "the DSL nests deeper than #{@max_depth} levels"
      end

      # The Symbol a Hash/keyword key denotes, or nil when the key is not a
      # plain (uninterpolated) symbol or string.
      #
      # @param node [Prism::Node]
      # @return [Symbol, nil]
      def literal_key(node)
        node.unescaped.to_sym if static_name?(node)
      end

      # @param scope [Symbol]
      # @return [String] human-readable scope name, article included
      def scope_label(scope)
        Vocabulary.label_for(scope)
      end

      # A short, author-facing description of a node the allowlist rejected.
      #
      # @param node [Prism::Node, nil]
      # @return [String]
      def describe(node)
        return "nothing" if node.nil?
        return describe_call(node) if node.is_a?(Prism::CallNode)

        NODE_LABELS.fetch(node.class) { humanize(node.class) }
      end

      # @param node [Prism::CallNode]
      # @return [String]
      def describe_call(node)
        return "`#{node.name}`" if node.receiver.nil?

        "a method call `#{node.name}` on #{describe(node.receiver)}"
      end

      # @param klass [Class] a Prism node class
      # @return [String] e.g. "a local variable write"
      def humanize(klass)
        words = klass.name.delete_prefix("Prism::").delete_suffix("Node")
                     .gsub(/([a-z\d])([A-Z])/, '\1 \2').downcase
        "#{words.start_with?(/[aeiou]/) ? "an" : "a"} #{words}"
      end
    end
  end
end
