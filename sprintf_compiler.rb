require 'thread' # Mutex

class SprintfCompiler
  attr_accessor :format
  attr_reader :expr
  attr_reader :proc
  
  INSTANCE_CACHE = { }

  def self.format fmt, args
    unless instance = INSTANCE_CACHE[fmt]
      fmt_dup = fmt.frozen? ? fmt : fmt.dup.freeze
      instance = INSTANCE_CACHE[fmt_dup] = self.new(fmt_dup)
      instance.compile!.define_format_method!
    end
    instance.fmt(args)
  end

  def initialize f
    @format = f
  end

  RADIXES = {?b => 2, ?o => 8, ?d => 10, ?i => 10, ?x => 16}
  RADIXES.each { | k, v | RADIXES[k.chr.upcase[0]] = v }
  RADIXES.freeze
  ALTERNATIVES = {"o" => "0", "b" => "0b", "B" => "0B", "x" => "0x", "X" => "0X"}

  EMPTY_STRING = ''.freeze
  SPACE        = ' '.freeze
  ZERO         = '0'.freeze
  MINUS        = '-'.freeze
  STAR         = '*'.freeze
  PERCENT      = '%'.freeze
  DOT          = '.'.freeze
  DQUOTE       = '"'.freeze

  PAD_SPACE    = "::#{self.name}::SPACE".freeze
  PAD_ZERO     = "::#{self.name}::ZERO".freeze

  CHAR_TABLE = [ ]
  (0 .. 255).each { | i | CHAR_TABLE[i] = i.chr.freeze }
  CHAR_TABLE.freeze

  def compile!
    @template = ''

    @arg_i = -1
    @arg_i_max = 0
    @arg_pos_used = false
    @arg_rel_used = false

    @var_i = 0
    @var_exprs = [ ]


    f = @format

    #           %flags       arg_pos       width        prec     type
    #           1            2             3            4        5
    while m = /%([-+0 ]+)?(?:([1-9])\$)?(?:(\d+|\*)(?:\.(\d+))?)?([scdiboxXfegEGp%])/.match(f)
      @m = m
      # $stderr.puts "m = #{m.to_a.inspect}"
      prefix_expr = nil

      gen_lit m.pre_match
      f = m.post_match

      flags = m[1] || EMPTY_STRING
      @flags_zero  = flags.include?(ZERO)
      @flags_minus = flags.include?(MINUS)
      @flags_space = flags.include?(SPACE)
      @arg_pos = m[2]
      @arg_pos &&= @arg_pos.to_i
      @width = m[3]
      precision = m[4]
      typec = (type = m[5])[0]

      if typec == ?%
        if @width || @flags_space || @flags_zero
          gen_error ArgumentError, "illegal format character - #{type}"
          return self
        end
        gen_lit(PERCENT)
        next
      end

      if @width_star = (@width == STAR)
        @width = get_arg 
      end
      break if @error_class

      arg_expr = get_arg
      break if @error_class

      direction = @flags_minus ? :ljust : :rjust

      pad = @flags_zero ? PAD_ZERO : PAD_SPACE

      expr = nil
      case typec
      when ?s
        pad = PAD_SPACE
        expr = "#{arg_expr}.to_s"

      when ?c
        pad = PAD_SPACE
        var = gen_var arg_expr
        gen_var_expr "#{var} = #{var}.to_int if #{var}.respond_to?(:to_int)"
        expr = "::#{self.class.name}::CHAR_TABLE[#{var} % 256]"
        @debug = true

      when ?d, ?i
        if @flags_space
          arg_expr = gen_var arg_expr
          expr = "#{arg_expr}.to_i.to_s(#{RADIXES[typec]})"
          str_var = gen_var expr
          gen_var_expr <<"END"
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
          gen_var_expr <<"END"
  if #{arg_expr} < 0
    #{arg_expr}    = - #{arg_expr}
    #{@width}      = #{@width} - 1
    #{prefix_expr} = ::#{self.class.name}::MINUS
  end
END
        end
        expr ||= "#{arg_expr}.to_i.to_s(#{RADIXES[typec]})"

      when ?b, ?o, ?x, ?X
        direction = :rjust if @flags_zero
        expr = "#{arg_expr}.to_i.to_s(#{RADIXES[typec]})"
        if typec == ?X
          expr << '.upcase'
        end

      when ?f, ?e, ?E, ?g, ?G
        if typec == ?e || typec == ?E
          precision = nil
        else
          precision ||= '4'
        end
        fmt = "%"
        fmt << SPACE if @flags_space
        fmt << MINUS if @flags_minus
        fmt << ZERO  if @flags_zero
        if @width
          # Width is dynamic.
          if @width_star
            width_var = gen_var @width
            fmt << '#{' << width_var << '}'
          else
            fmt << @width
          end
        end
        fmt << DOT << precision if precision
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
        expr = "#{arg_expr}.inspect"
      
      end

      unless expr
        gen_error ArgumentError, "malformed format string - #{m[0]}"
        return self
      end

      if prefix_expr
        gen_expr prefix_expr
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
          gen_var_expr <<"END"
#{expr_var} = (#{width_var} >= 0 ? #{expr_var}.#{direction}(#{width_var}, #{pad}) : #{expr_var}.#{direction_other}(- #{width_var}, #{pad}))
END
          expr = expr_var
        end
      end

      gen_expr expr
    end
    
    gen_lit f

    proc_expr

    self
  end

  def get_arg
    if @arg_pos
      @arg_pos_used = true
      arg_i = @arg_pos - 1
    else
      @arg_rel_used = true
      arg_i = (@arg_i += 1)
    end
    if @arg_rel_used && @arg_pos_used
      return gen_error ArgumentError, "Cannot use both positional and relative formats in #{@m[0]}" # FIXME
    end
    @arg_i_max = arg_i if @arg_i_max < arg_i
    "args[#{arg_i}]"
  end


  ####################################################################
  # Code generation
  #

  def gen_error cls, fmt
    @error_class, @error_msg = cls, fmt
    nil
  end

  def gen_var expr = 'nil'
    var = "l_#{@var_i +=1 }"
    @var_exprs << "#{var} = #{expr}"
    var
  end

  def gen_var_expr expr
    @var_exprs << expr
  end

  def gen_lit str
    @template << str.inspect[1 .. -2] unless str.empty?
  end

  def gen_expr expr
    # peephole optimization for to_s(10).
    expr.sub!(/\.to_s\(10\)$/, '.to_s') 

    # peephole optimization for implicit #to_s call during #{...}
    expr.sub!(/\.to_s$/, '') 

    @template << '#{' << expr << '}'
  end
  
  ####################################################################
  # Ruby compilation and invocation.
  #

  def proc
    @proc ||=
      eval <<"END", __FILE__, __LINE__
lambda do | args |
#{proc_expr}
end
END
  rescue Exception => err
    $stderr.puts "ERROR: #{err} in\n#{proc_expr}"
    gen_error err.class, err.message
    @proc = lambda { | args | raise @error_class, @error_message }
  end

  def proc_expr
    @proc_expr ||= <<"END"
  raise ArgumentError, "too few arguments" if args.size < #{@arg_i_max + 1}
  #{@var_exprs * "\n"}
  "#{@template}"
END
  end

  def define_format_method!
    instance_eval <<"END"
def self.fmt args
  # $stderr.puts "\#{self}.fmt \#{args.inspect}\n\#{caller.inspect}"
  raise @error_class, @error_msg if @error_class
  #{proc_expr}
end
alias :% :fmt
END
   self
  end

  def fmt args
    raise @error_class, @error_msg if @error_class
    define_format_method!
    proc.call(args)
  end
  alias :% :fmt

end


if $0 == __FILE__
require 'pp'

def trap_error 
  [ :ok, yield ]
rescue Exception => err
  [ err.class, err.message ]
end

[ '', 
  [ '%', 's', 'c', 'd', 'x', 'b', 'X', 'f', 'e', 'g', 'E', 'G', 'p' ].map do | x |
    [
     "%#{x}", 
     "%1$#{x}",
     "%2$#{x}",
     "% #{x}",
     "%0#{x}",
     "%10#{x}",
     "%-10#{x}",
     "%010#{x}",
     "%0-10#{x}",
     "%*#{x}",
     "%-*#{x}", 
    ]
  end,
].flatten.each do | x |
  fmt = "alks #{x} jdfa"
  [ [ 20, 42 ], [ -20, -42 ] ].each do | args |
    $stdout.puts <<"END"
format:   #{fmt.inspect} % #{args.inspect}
END

    sc = SprintfCompiler.new(fmt).compile!.define_format_method!

    expected = trap_error { sc.format % args }
    result   = trap_error { sc % args }

    if result != expected
      $stdout.puts <<"END"
###########################################
# ERROR:
format:   #{fmt.inspect} % #{args.inspect}
expected: #{expected.inspect}
result:   #{result.inspect}

END
        pp sc
      else
    $stdout.puts <<"END"
result:   #{result.inspect}

END
      end
    end
end

end

