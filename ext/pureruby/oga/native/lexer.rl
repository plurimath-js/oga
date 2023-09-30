%%machine ruby_lexer;

#
# Lexer support class for Ruby.
#
# The Lexer class contains the raw Ragel loop and calls back in to Ruby land
# whenever a Ragel action is needed similar to the C extension setup.
#
# This class requires Ruby land to first define the `Oga::XML` namespace.
#
module Oga
  module XML
    class Lexer
      %% write data nofinal;

      # Runs the bulk of the Ragel loop and calls back in to Ruby.
      #
      # This method pulls its data in from the instance variable `@data`. The
      # Ruby side of the Lexer class should set this variable to a String in its
      # constructor method. Encodings are passed along to make sure that token
      # values share the same encoding as the input.
      #
      # This method always returns nil.
    
      def advance_native(rb_str)
        html_p = html?

        encoding = rb_str.encoding

        data  = rb_str.chars.map(&:ord)
        ts    = 0
        te    = 0
        p     = 0
        mark  = 0
        lines = @lines || 0
        pe    = data.length
        eof   = data.length

        id_advance_line        = "advance_line"
        id_on_attribute        = "on_attribute"
        id_on_attribute_ns     = "on_attribute_ns"
        id_on_cdata_start      = "on_cdata_start"
        id_on_cdata_body       = "on_cdata_body"
        id_on_cdata_end        = "on_cdata_end"
        id_on_comment_start    = "on_comment_start"
        id_on_comment_body     = "on_comment_body"
        id_on_comment_end      = "on_comment_end"
        id_on_doctype_end      = "on_doctype_end"
        id_on_doctype_inline   = "on_doctype_inline"
        id_on_doctype_name     = "on_doctype_name"
        id_on_doctype_start    = "on_doctype_start"
        id_on_doctype_type     = "on_doctype_type"
        id_on_element_end      = "on_element_end"
        id_on_element_name     = "on_element_name"
        id_on_element_ns       = "on_element_ns"
        id_on_element_open_end = "on_element_open_end"
        id_on_proc_ins_end     = "on_proc_ins_end"
        id_on_proc_ins_name    = "on_proc_ins_name"
        id_on_proc_ins_start   = "on_proc_ins_start"
        id_on_proc_ins_body    = "on_proc_ins_body"
        id_on_string_body      = "on_string_body"
        id_on_string_dquote    = "on_string_dquote"
        id_on_string_squote    = "on_string_squote"
        id_on_text             = "on_text"
        id_on_xml_decl_end     = "on_xml_decl_end"
        id_on_xml_decl_start   = "on_xml_decl_start"

        %% write exec;

        @lines = lines

        nil
      end

      # Resets the internal state of the lexer.
      def reset_native
        @act   = 0;
        @top   = 0;
        @stack = Array.new(4, 0)
        @cs    = self.class.ruby_lexer_start

        nil
      end

      # Calls back in to Ruby land passing the current token value along.
      #
      # This method calls back in to Ruby land based on the method name
      # specified in `name`. The Ruby callback should take one argument. This
      # argument will be a String containing the value of the current token.
      def callback(name, data, enc, ts, te)
        bytelist = data[ts, te - ts].pack('U*').force_encoding(enc)
        send(name, bytelist)
      end

      def callback_simple(name)
        send(name)
      end

      def html_script_p
        html_script?  # method not defined here
      end

      def html_style_p
        html_style?  # method not defined here
      end

      # Ragel generated code will reference class methods
      def method_missing(method, *args, **kwargs, &block)
        self.class.send(method, *args, **kwargs, &block)
      end
    end
  end
end

%%{
    variable act @act;
    variable cs @cs;
    variable stack @stack;
    variable top @top;

    include base_lexer "base_lexer_rubified.rl";
}%%
