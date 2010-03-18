require 'thread' # Mutex

class SprintfCompiler
  attr_accessor :format
  attr_reader :expr
  attr_reader :proc
  
  INSTANCE_CACHE = { }
  INSTANCE_MUTEX = Mutex.new

  def self.format fmt, args
    unless instance = INSTANCE_CACHE[fmt]
      INSTANCE_MUTEX.synchronize do 
        fmt_dup = fmt.frozen? ? fmt : fmt.dup.freeze
        instance = INSTANCE_CACHE[fmt_dup] = self.new(fmt_dup)
        instance.compile!.define_format_method!
      end
    end
    instance.fmt(args)
  end

  def initialize f
    @format = f
  end

  RADIXES = {"b" => 2, "o" => 8, "d" => 10, "x" => 16}
  RADIXES.each { | k, v | RADIXES[k.upcase] = v }
  RADIXES.freeze
  ALTERNATIVES = {"o" => "0", "b" => "0b", "B" => "0B", "x" => "0x", "X" => "0X"}

  RELATIVE_ARG_EXPR = "args[argi += 1]"
  
  EMPTY_STRING = ''.freeze
  SPACE        = ' '.freeze
  ZERO         = '0'.freeze
  MINUS        = '-'.freeze
  STAR         = '*'.freeze
  PERCENT      = '%'.freeze
  DOT          = '.'.freeze

  PAD_SPACE    = "::#{self.name}::SPACE".freeze
  PAD_ZERO     = "::#{self.name}::ZERO".freeze

  CHAR_TABLE = { }
  (0 .. 255).each { | i | CHAR_TABLE[i] = i.chr.freeze }
  CHAR_TABLE.freeze

  def compile!
    @template = ''
    @argi = -1
    @var_i = 0
    @var_exprs = [ ]

    f = @format

    #          %flag       width       . prec     kind
    #           1          2             3        4
    while m = /%([-+0]+)?(?:(\d+|\*)(?:\.(\d+))?)?([scdboxBOXfg%])/.match(f)
      gen_lit m.pre_match
      f = m.post_match
      # $stderr.puts "m = #{m.to_a.inspect}"

      if (type = m[4]) == PERCENT
        gen_lit(PERCENT)
        next
      end

      flags = m[1] || EMPTY_STRING
      direction = flags.include?(MINUS) ? :ljust : :rjust

      pad = PAD_SPACE
      pad = PAD_ZERO if flags.include?(ZERO)

      width = m[2]
      width = "args[#{@argi += 1}]" if width == STAR

      precision = m[3]

      arg_expr = "args[#{@argi += 1}]"

      case type[0]
      when ?s
        pad = PAD_SPACE
        expr = "#{arg_expr}.to_s"
      when ?c
        pad = PAD_SPACE
        var = gen_var arg_expr
        gen_var_expr "#{var} = #{var}.to_int if #{var}.respond_to?(:to_int)"
        expr = "::#{self.class.name}::CHAR_TABLE[#{var} % 256]"
        @debug = true
      when ?d
        if flags.include?(ZERO)
          direction = :rjust 
          var = gen_var arg_expr
          gen_var_expr <<"END"
  if #{var} < 0
    
  end
END
          arg_expr = var
        end
        expr = "#{arg_expr}.to_i.to_s(#{RADIXES[type]})"
      when ?b, ?o, ?x, ?B, ?O, ?X
        direction = :rjust if flags.include?(ZERO)
        expr = "#{arg_expr}.to_i.to_s(#{RADIXES[type]})"
        if type == 'X'
          expr << '.upcase'
        end
      when ?f, ?F, ?g, ?G
        fmt = "%"
        fmt << SPACE if pad == PAD_SPACE
        fmt << MINUS if flags.include?(MINUS)
        fmt << ZERO  if pad == PAD_ZERO
        fmt << width if width
        fmt << DOT << precision if precision
        fmt << type
        expr = "#{arg_expr}.to_f.send(:to_formatted_s, #{fmt.inspect})"
      else
        @error_class = ArgumentError
        @error_msg = "malformed format string - #{m[0]}"
        return self
      end

      if width 
        expr << ".#{direction}(#{width}"
        expr << ', ' << pad if pad != PAD_SPACE
        expr << ")"
      end

      gen_expr expr
    end
    gen_lit f

    proc_expr

    self
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
  
  def proc
    @proc ||=
      eval <<"END", __FILE__, __LINE__
lambda do | args |
#{proc_expr}
end
END
  rescue Exception => err
    $stderr.puts "ERROR: #{err} in\n#{proc_expr}"
    @error_class = err.class
    @error_msg   = err.message
    @proc = lambda { | args | raise @error_class, @error_message }
  end

  def proc_expr
    @proc_expr ||= <<"END"
  raise ArgumentError, "too few arguments" if args.size < #{@argi + 1}
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

  def % args
    raise @error_class, @error_msg if @error_class
    proc.call(args)
  end

end


if $0 == __FILE__
require 'pp'

[ '', 
  [ 's', 'c', 'd', 'x', 'b', 'X' ].map do | x |
    [
     "%#{x}", 
     "%10#{x}",
     "%-10#{x}",
     "%010#{x}",
     "%0-10#{x}",
     "%*#{x}",
     "%-*#{x}", 
    ]
  end,
  [ '%f', '%g' ],
].flatten.each do | x |
  fmt = "alks #{x} jdfa"
  [ [ 20, 42 ], [ -20, -42 ] ].each do | args |
    sc = SprintfCompiler.new(fmt).compile!.define_format_method!
    expected = sc.format % args 
    result = sc % args
    if result != expected
      $stderr.puts <<"END"
###########################################
# ERROR:
format:   #{fmt.inspect} % #{args.inspect}
expected: #{expected.inspect}
result:   #{result.inspect}

END
        pp sc
      else
    $stdout.puts <<"END"
format:   #{fmt.inspect} % #{args.inspect}
result:   #{result.inspect}

END
      end
    end
end

end

