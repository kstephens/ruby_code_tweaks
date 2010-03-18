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
        instance.compile!.proc
      end
    end
    instance % args
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

  PAD_SPACE    = "::#{self.name}::SPACE".freeze
  PAD_ZERO     = "::#{self.name}::ZERO".freeze

  def compile!
    @template = ''
    @argi = -1
    f = @format.dup
    #          %flag       width       . prec     kind
    #           1          2             3        4
    while m = /%([-+0]+)?(?:(\d+|\*)(?:\.(\d+))?)?([sdboxBOXfg%])/.match(f)
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

      case type
      when 's'
        pad = PAD_SPACE
        expr = "#{arg_expr}.to_s"
      when 'd', 'b', 'u', 'x', 'B', 'U', 'X'
        direction = :rjust if flags.include?(ZERO)
        expr = "#{arg_expr}.to_i.to_s(#{RADIXES[type]})"
        if type == 'X'
          expr << '.upcase'
        end
      when 'f', 'F', 'g', 'G'
        fmt = "%"
        fmt << SPACE if pad == PAD_SPACE
        fmt << MINUS if flags.include?(MINUS)
        fmt << ZERO  if pad == PAD_ZERO
        fmt << width if width
        fmt << '.' << precision if precision
        fmt << type
        expr = "#{arg_expr}.to_f.send(:to_formatted_s, #{fmt.inspect})"
      else
        @error = [ ArgumentError, "malformed format string - #{m[0]}" ]
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
      eval proc_expr
  rescue Exception => err
    $stderr.puts "ERROR: #{err} in\n#{proc_expr}"
    @error = [ err.class, err.message ]
    @proc = lambda { | args | raise @error[0], @error[1] }
  end

  def proc_expr
    @proc_expr ||= <<"END"
lambda do | args |
  raise ArgumentError, "too few arguments" if args.size < #{@argi + 1}
  "#{@template}"
end
END
  end

  def % args
    raise @error[0], @error[1] if @error
    proc.call(args)
  end

end


if $0 == __FILE__
require 'pp'

[ '', 
  [ 's', 'd', 'x', 'b', 'X' ].map do | x |
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
  args = [ 20, 42 ]
  sc = SprintfCompiler.new(fmt).compile!
  expected = sc.format % args 
  result = sc % args
  if result != expected
    $stderr.puts <<"END"
ERROR:
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

