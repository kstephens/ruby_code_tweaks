
class SprintfCompiler
  attr_accessor :format
  attr_reader :expr
  attr_reader :proc
  
  INSTANCE_CACHE = { }
  def self.instance fmt
    unless instance = (fmt && INSTANCE_CACHE[fmt])
      fmt_dup = fmt.frozen? ? fmt : fmt.dup.freeze
      instance = INSTANCE_CACHE[fmt_dup] = self.new(fmt_dup)
      instance.define_format_method!
    end
    instance
  end

  def self.fmt fmt, args
    instance(fmt) % args
  end

  def initialize f
    @format = f
  end

  RADIXES = {?b => 2, ?o => 8, ?d => 10, ?i => 10, ?x => 16}
  RADIXES.dup.each { | k, v | RADIXES[k.chr.upcase[0]] = v }
  RADIXES.freeze
  RADIX_MAX_CHAR = { }
  RADIXES.each do | k, r |
    RADIX_MAX_CHAR[r] = (r - 1).to_s(r).freeze
  end
  RADIX_MAX_CHAR.freeze

  ALTERNATIVES = {?o => "0", ?b => "0b", ?B => "0B", ?x => "0x", ?X => "0X"}

  EMPTY_STRING = ''.freeze
  SPACE        = ' '.freeze
  HASH         = '#'.freeze
  ZERO         = '0'.freeze
  MINUS        = '-'.freeze
  STAR         = '*'.freeze
  PERCENT      = '%'.freeze
  DOT          = '.'.freeze
  DOTDOT       = '..'.freeze
  DQUOTE       = '"'.freeze

  F_LC         = 'f'.freeze

  PAD_SPACE    = "::#{self.name}::SPACE".freeze
  PAD_ZERO     = "::#{self.name}::ZERO".freeze
  PAD_DOTDOT   = "::#{self.name}::DOTDOT".freeze

  DEFAULT_F_PREC = '6'.freeze
  DEFAULT_G_PREC = '4'.freeze

  CHAR_TABLE = [ ]
  (0 .. 255).each { | i | CHAR_TABLE[i] = i.chr.freeze }
  CHAR_TABLE.freeze

  def compile!
    return self if @compiled
    @compiled = true
    @str_template = ''

    @arg_i = @arg_i_max = -1
    @arg_pos_used = false
    @arg_rel_used = false

    @var_i = 0
    @exprs = [ ]


    f = @format

    #           %flags        arg_pos       width        prec     type
    #           1             2             3            4        5
    while m = /%([-+0# ]+)?(?:([1-9])\$)?(?:(\d+|\*+)(?:\.(\d+))?)?([scdiboxXfegEGp%])/.match(f)
      @m = m
      # $stderr.puts "m = #{m.to_a.inspect}"
      prefix_expr = nil

      gen_str_lit m.pre_match
      f = m.post_match

      flags = m[1] || EMPTY_STRING
      @flags_zero  = flags.include?(ZERO)
      @flags_minus = flags.include?(MINUS)
      @flags_space = flags.include?(SPACE)
      @flags_alternative = flags.include?(HASH)
      @arg_pos = m[2]
      @arg_pos &&= @arg_pos.to_i
      @width = m[3]
      @width_star = @width && @width.count(STAR)
      @width_star = nil if @width_star && @width_star < 1

      @precision = m[4]
      @limit = nil
      typec = (type = m[5])[0]

      if typec == ?%
        if @arg_pos || @width_star # "%$1%" or "%*%"
          gen_arg 
        end
        if @width || @flags_space || @flags_zero
          return gen_error(ArgumentError, "illegal format character - #{type}")
        end
        gen_str_lit(PERCENT)
        next
      end

      # Get the width argument.
      if @width_star
        @width = gen_arg 
      end
      break if @error_class

      # Check for multiple width arguments.
      if @width_star && @width_star > 1
        return gen_error(ArgumentError, "width given twice")
      end

      # Get the value argument.
      arg_expr = gen_arg
      break if @error_class

      direction = @flags_minus ? :ljust : :rjust

      pad = @flags_zero ? PAD_ZERO : PAD_SPACE

      expr = nil
      case typec
      when ?s
        pad = PAD_SPACE
        @limit = @precision
        expr = "#{arg_expr}.to_s"

      when ?c
        pad = PAD_SPACE
        arg_expr = gen_var arg_expr
        gen_expr "#{arg_expr} = #{arg_expr}.to_int if #{arg_expr}.respond_to?(:to_int)"
        gen_expr %Q{raise RangeError, "bignum too big to convert into \`long'" unless Fixnum === #{arg_expr}}
        expr = "::#{self.class.name}::CHAR_TABLE[#{arg_expr} % 256]"
        @debug = true

      when ?d, ?i
        arg_expr = gen_integer arg_expr
        if @flags_space
          arg_expr = gen_var arg_expr
          expr = "#{arg_expr}.to_s"
          str_var = gen_var expr
          gen_expr <<"END"
  if #{arg_expr} >= 0
    #{str_var} = ' ' + #{str_var}
  end
END
          expr = str_var
        end
        if @flags_zero && @width
          direction = :rjust 
          @width  = gen_var @width
          arg_expr = gen_var arg_expr
          prefix_expr = gen_var "::#{self.class.name}::EMPTY_STRING"
          gen_expr <<"END"
  if #{arg_expr} < 0
    #{arg_expr}    = - #{arg_expr}
    #{@width}      = #{@width} - 1
    #{prefix_expr} = ::#{self.class.name}::MINUS
  end
END
        end
        expr ||= "#{arg_expr}.to_s"

      when ?b, ?o, ?x, ?X
        radix = RADIXES[typec] or raise ArgumentError
        radix_char = "::#{self.class.name}::RADIX_MAX_CHAR[#{radix}]"
        radix_char << '.upcase' if typec == ?X
        arg_expr = gen_integer arg_expr
        direction = :rjust if @flags_zero
        # pad = PAD_SPACE unless @flags_zero
        if ! (@flags_space || @flags_plus)
          pad_digit = gen_var "#{arg_expr} < 0 ? #{radix_char} : #{PAD_ZERO}"
          if @flags_zero
            pad = pad_digit
            pad_digit = gen_var radix_char
          end
          str_expr = gen_var "#{arg_expr}.to_s(#{radix})"
          gen_expr <<"END"
if #{arg_expr} < 0
  #{arg_expr}_len = #{str_expr}.size
  #{arg_expr}_max = (#{pad_digit} * #{arg_expr}_len).to_i(#{radix})
  #{str_expr} = (#{arg_expr}_max + #{arg_expr} + 1).to_s(#{radix})
  #{str_expr}.slice!(0, 1) if #{str_expr}[0] == #{pad_digit}[0] && #{str_expr}[1] == #{pad_digit}[0]
  #{str_expr}.insert(0, #{PAD_DOTDOT}) unless #{@flags_zero.inspect}
end
END
          expr = str_expr
        elsif @flags_space 
          arg_expr = gen_var arg_expr
          expr = "#{arg_expr}.to_s(#{radix})"
          expr = gen_var expr
          gen_expr <<"END"
if #{arg_expr} >= 0
  #{expr}.insert(0, #{PAD_SPACE})
end
END
        else
          expr = "#{arg_expr}.to_s(#{radix})"
        end
        if @flags_alternative && (alt = ALTERNATIVES[typec])
          gen_str_lit alt
        end
        if typec == ?X
          expr << '.upcase'
        end

      when ?f, ?e, ?E, ?g, ?G
        case typec
        when ?g, ?G
          @precision ||= DEFAULT_F_PREC
          type = F_LC if @flags_alternate
        when ?e, ?E
          # @precision = nil
        else
          @precision ||= DEFAULT_F_PREC
        end

        fmt = "%"
        fmt << SPACE if @flags_space
        fmt << MINUS if @flags_minus
        fmt << ZERO  if @flags_zero
        fmt << HASH  if @flags_alternative
        if @width
          # Width is dynamic.
          if @width_star
            width_var = gen_var @width
            fmt << '#{' << width_var << '}'
          else
            fmt << @width
          end
          @width = nil
        end
        fmt << DOT << @precision if @precision
        #fmt << (typec == ?g ? F_LC : type)
        fmt << type

        # Width is dynamic.
        if @width_star
          fmt = %Q{"#{fmt}"}
        else
          fmt = fmt.inspect
        end
        # $stdout.puts "  fmt = #{fmt.inspect}"

        expr = "#{arg_expr}.to_f"

        case RUBY_DESCRIPTION
        when /^ruby/
          expr = "Kernel.sprintf(#{fmt}, #{expr})"
        when /^rubinius/
          expr = "#{expr}.send(:to_formatted_s, #{fmt})"
        end

      when ?p
        pad = PAD_SPACE
        @limit = @precision
        expr = "#{arg_expr}.inspect"
      end

      unless expr
        return gen_error(ArgumentError, "malformed format string - #{m[0]}")
      end

      if prefix_expr
        gen_str_expr prefix_expr
      end

      if @width 
        # Optimize for constant width:
        if @width =~ /^\d+$/
          expr << ".#{direction}(#{@width}"
          expr << ', ' << pad if pad != PAD_SPACE
          expr << ")"
        else
=begin
          $stdout.puts "  direction   = #{direction.inspect}"
          $stdout.puts "  flags_minus = #{@flags_minus.inspect}"
=end
          direction = :rjust if @flag_minus
          direction_other = (direction == :ljust ? :rjust : :ljust)
          @width = @width + (@flags_minus ? '.abs' : '') if @flags_minus

          expr_var  = gen_var expr
          width_var = gen_var @width
          gen_expr <<"END"
#{expr_var} = (#{width_var} >= 0 ? #{expr_var}.#{direction}(#{width_var}, #{pad}) : #{expr_var}.#{direction_other}(- #{width_var}, #{pad}))
END
          expr = expr_var
        end
      end

      if @limit
        expr << "[0, #{@limit}]"
      end

      gen_str_expr expr
    end

    gen_str_lit f

    proc_expr

    self
  end

  ####################################################################
  # Code generation
  #

  def gen_arg
    if @arg_pos
      @arg_pos_used = true
      arg_i = @arg_pos - 1
      if @arg_rel_used
        gen_error(ArgumentError, "numbered(#{arg_i + 1}) after unnumbered(#{@arg_i + 1})")
        return nil
      end
    else
      @arg_rel_used = true
      arg_i = (@arg_i += 1)
      if @arg_pos_used
        gen_error(ArgumentError, "unnumbered(#{arg_i + 1}) mixed with numbered")
        return nil
      end
    end
    @arg_i_max = arg_i if @arg_i_max < arg_i
    "args[#{arg_i}]"
  end

  def gen_integer expr
    var = gen_var expr
    gen_expr <<"END"
      unless #{var}.respond_to?(:full_to_i)
        if #{var}.respond_to?(:to_int)
          #{var} = #{var}.to_int
        elsif #{var}.respond_to?(:to_i)
          #{var} = #{var}.to_i
        end
      end
      #{var} = #{var}.full_to_i if #{var}.respond_to?(:full_to_i)
      #{var} = 0 if #{var}.nil?
      raise TypeError, "can't convert \#{#{var}} into Integer" unless Integer === #{var}
END
    var
  end
  
  def gen_error cls, fmt
    @error_class, @error_msg = cls, fmt
    self
  end

  def gen_var expr = 'nil'
    var = "l#{@var_i +=1 }"
    @exprs << "#{var} = #{expr}"
    var
  end

  def gen_expr expr
    @exprs << expr
  end

  def gen_str_lit str
    @str_template << str.inspect[1 .. -2] unless str.empty?
  end

  def gen_str_expr expr
    # peephole optimization for Integer#to_s(10).
    expr.sub!(/\.to_s\(10\)$/, '.to_s') 

    # peephole optimization for implicit #to_s call during #{...}
    expr.sub!(/\.to_s$/, '') 

    @str_template << '#{' << expr << '}'
  end
  
  ####################################################################
  # Ruby compilation and invocation.
  #

  def proc
    @proc ||=
      eval <<"END" # , __FILE__, __LINE__
lambda do | args |
#{proc_expr}
end
END
  rescue Exception => err
    $stderr.puts "ERROR: #{err} in\n#{proc_expr}"
    gen_error err.class, err.message
    @proc = lambda { | args | raise err.class, err.message }
  end

  def proc_expr
    @proc_expr ||= 
      compile! && <<"END"
  #{arg_check_expr}
  #{@exprs * "\n"}
  "#{@str_template}"
END
  end

  def arg_check_expr
    if @arg_i_max != -1
      %Q{
if (args = args.to_a).size < #{@arg_i_max + 1}
  raise ArgumentError, "too few arguments"
end
}
    else
      EMPTY_STRING
    end + 
    if @error_class
      %Q{raise ::#{@error_class.name}, #{@error_msg.inspect}\n}
    else
      EMPTY_STRING
    end
  end

  def define_format_method!
    compile!
    instance_eval <<"END"
def self.fmt args
  # $stderr.puts "\#{self}.fmt \#{@format.inspect} \#{args.inspect}\n\#{caller.inspect}"
  #{proc_expr}
end
alias :% :fmt
END
   self
  end

  def fmt args
    define_format_method!
    # require 'pp'; pp [ self, args ]
    proc.call(args)
  end
  alias :% :fmt

  self.new("%s").fmt([ 123 ])
end


