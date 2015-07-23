module Oga
  module XPath
    ##
    # Compiling of XPath ASTs into Ruby code.
    #
    # The Compiler class can be used to turn an XPath AST into Ruby source code
    # that can be executed to match XML nodes in a given input document/element.
    # Compiled source code is cached per expression, removing the need for
    # recompiling the same expression over and over again.
    #
    # @private
    #
    class Compiler
      # @return [Oga::LRU]
      CACHE = LRU.new

      # Wildcard for node names/namespace prefixes.
      STAR = '*'

      # Node types that require a NodeSet to push nodes into.
      RETURN_NODESET = [:path, :absolute_path, :axis, :predicate]

      ##
      # Compiles and caches an AST.
      #
      # @see [#compile]
      #
      def self.compile_with_cache(ast)
        CACHE.get_or_set(ast) { new.compile(ast) }
      end

      ##
      # Compiles an XPath AST into a Ruby Proc.
      #
      # @param [AST::Node] ast
      # @return [Proc]
      #
      def compile(ast)
        document = node_literal
        matched  = matched_literal

        if return_nodeset?(ast)
          ruby_ast = process(ast, document) { |node| matched.push(node) }
        else
          ruby_ast = process(ast, document)
        end

        vars = variables_literal.assign(literal('nil'))

        proc_ast = literal('lambda').add_block(document, vars) do
          if return_nodeset?(ast)
            matched.assign(literal(XML::NodeSet).new)
              .followed_by(ruby_ast)
              .followed_by(matched)
          else
            ruby_ast
          end
        end

        generator = Ruby::Generator.new
        source    = generator.process(proc_ast)

        eval(source)
      end

      ##
      # Processes a single XPath AST node.
      #
      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      #
      def process(ast, input, &block)
        send("on_#{ast.type}", ast, input, &block)
      end

      ##
      # Processes a relative path.
      #
      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      #
      def on_path(ast, input, &block)
        ruby_ast   = nil
        var_name   = node_literal
        last_index = ast.children.length - 1

        ast.children.reverse_each.with_index do |child, index|
          # The first block should operate on the variable set in "input", all
          # others should operate on the child variables ("node").
          input_var = index == last_index ? input : var_name

          # The last segment of the path should add the code that actually
          # pushes the matched node into the node set.
          if index == 0
            ruby_ast = process(child, input_var, &block)
          else
            ruby_ast = process(child, input_var) { ruby_ast }
          end
        end

        ruby_ast
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_absolute_path(ast, input, &block)
        if ast.children.empty?
          matched_literal.push(input.root_node)
        else
          on_path(ast, input.root_node, &block)
        end
      end

      ##
      # Dispatches the processing of axes to dedicated methods. This works
      # similar to {#process} except the handler names are "on_axis_X" with "X"
      # being the axis name.
      #
      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      #
      def on_axis(ast, input, &block)
        name, test = *ast.children

        handler = name.gsub('-', '_')

        send(:"on_axis_#{handler}", test, input, &block)
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_axis_child(ast, input, &block)
        child     = node_literal
        condition = process(ast, child, &block)

        input.children.each.add_block(child) do
          condition.if_true { yield child }
        end
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_axis_attribute(ast, input)
        input.is_a?(XML::Element).if_true do
          attribute = literal('attribute')

          input.attributes.each.add_block(attribute) do
            name_match = match_name_and_namespace(ast, attribute)

            if name_match
              name_match.if_true { yield attribute }
            else
              yield attribute
            end
          end
        end
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_axis_ancestor_or_self(ast, input, &block)
        parent = literal('parent')

        self_test = process(ast, input, &block).if_true { yield input }

        ancestors_test = input.each_ancestor.add_block(parent) do
          process(ast, parent, &block).if_true { yield parent }
        end

        self_test.followed_by(ancestors_test)
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_axis_ancestor(ast, input, &block)
        parent = literal('parent')

        input.each_ancestor.add_block(parent) do
          process(ast, parent, &block).if_true { yield parent }
        end
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_predicate(ast, input, &block)
        test, predicate = *ast

        if number?(predicate)
          on_index_predicate(test, predicate, input, &block)
        else
          on_expression_predicate(test, predicate, input, &block)
        end
      end

      ##
      # Processes an index predicate such as `foo[10]`.
      #
      # @param [AST::Node] test
      # @param [AST::Node] predicate
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      #
      def on_index_predicate(test, predicate, input)
        int1      = literal('1')
        index     = to_int(predicate)
        index_var = literal('index')

        inner = process(test, input) do |matched_test_node|
          index_var.eq(index).if_true { yield matched_test_node }
            .followed_by(index_var.assign(index_var + int1))
        end

        index_var.assign(int1).followed_by(inner)
      end

      ##
      # Processes a predicate using an expression.
      #
      # This method generates Ruby code that roughly looks like the following:
      #
      #     if catch :predicate_matched do
      #         node.children.each do |node|
      #
      #         if some_condition_that_matches_a_predicate
      #           throw :predicate_matched, true
      #         end
      #
      #         nil
      #       end
      #
      #       matched.push(node)
      #     end
      #
      # @param [AST::Node] test
      # @param [AST::Node] predicate
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      #
      def on_expression_predicate(test, predicate, input)
        catch_arg = symbol(:predicate_matched)

        process(test, input) do |matched_test_node|
          catch_block = send_message('catch', catch_arg).add_block do
            inner = process(predicate, matched_test_node) do
              send_message('throw', catch_arg, literal('true'))
            end

            # Ensure that the "catch" only returns a value when "throw" is
            # actually invoked.
            inner.followed_by(literal('nil'))
          end

          catch_block.if_true { yield matched_test_node }
        end
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_test(ast, input)
        condition  = element_or_attribute(input)
        name_match = match_name_and_namespace(ast, input)

        name_match ? condition.and(name_match) : condition
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_eq(ast, input)
        left, right = *ast

        process(left, input).eq(process(right, input))
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_string(ast, *)
        string(ast.children[0])
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_int(ast, *)
        literal(ast.children[0].to_f.to_s)
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_float(ast, *)
        literal(ast.children[0].to_s)
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def on_var(ast, input)
        vars = variables_literal
        name = ast.children[0]

        variables_literal.and(variables_literal[string(name)])
          .or(send_message('raise', string("Undefined XPath variable: #{name}")))
      end

      private

      # @param [#to_s] value
      # @return [Oga::Ruby::Node]
      def literal(value)
        Ruby::Node.new(:lit, [value.to_s])
      end

      # @param [#to_s] value
      # @return [Oga::Ruby::Node]
      def string(value)
        Ruby::Node.new(:string, [value.to_s])
      end

      # @param [String] value
      # @return [Oga::Ruby::Node]
      def symbol(value)
        Ruby::Node.new(:symbol, [value.to_sym])
      end

      # @param [String] name
      # @param [Array] args
      # @return [Oga::Ruby::Node]
      def send_message(name, *args)
        Ruby::Node.new(:send, [nil, name, *args])
      end

      # @param [Oga::Ruby::Node] node
      # @return [Oga::Ruby::Node]
      def element_or_attribute(node)
        node.is_a?(XML::Attribute).or(node.is_a?(XML::Element))
      end

      # @param [AST::Node] ast
      # @param [Oga::Ruby::Node] input
      # @return [Oga::Ruby::Node]
      def match_name_and_namespace(ast, input)
        ns, name = *ast

        condition = nil

        if name != STAR
          condition = input.name.eq(string(name))
        end

        if ns and ns != STAR
          ns_match  = input.namespace_name.eq(string(ns))
          condition = condition ? condition.and(ns_match) : ns_match
        end

        condition
      end

      # @return [Oga::Ruby::Node]
      def matched_literal
        literal('matched')
      end

      # @return [Oga::Ruby::Node]
      def node_literal
        literal('node')
      end

      # @return [Oga::Ruby::Node]
      def variables_literal
        literal('variables')
      end

      # @param [AST::Node] ast
      # @return [Oga::Ruby::Node]
      def to_int(ast)
        literal(ast.children[0].to_i.to_s)
      end

      # @param [AST::Node] ast
      # @return [TrueClass|FalseClass]
      def number?(ast)
        ast.type == :int || ast.type == :float
      end

      # @param [AST::Node] ast
      # @return [TrueClass|FalseClass]
      def return_nodeset?(ast)
        RETURN_NODESET.include?(ast.type)
      end
    end # Compiler
  end # XPath
end # Oga