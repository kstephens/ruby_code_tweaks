require 'sprintf_compiler'
require 'pp'

def trap_error 
  $error = nil
  [ :ok, yield ]
rescue Exception => err
  $error = err
  [ err.class, err.message ]
end

class AnyException < Exception; end

def check fmt, args, opts = { }
  $stdout.puts <<"END"
format:   #{fmt.inspect} % #{args.inspect}
END
  
  sc = nil
  expected = trap_error do
    fmt % args
  end
  result   = trap_error do
    sc = SprintfCompiler.new(fmt).define_format_method!
    sc % args
  end

  if opts[:any_error] || ENV['ANY_ERR']
    [ result, expected ].each do | a |
      if Class === a[0] && Class === result[0] && Class === expected[0]
        a[0] = AnyException
        a[1] = :any_msg
      end
    end
  end

  if opts[:ignore_error] || ENV['IGNORE_ERR']
    [ result, expected ].each do | a |
      if Class === a[0]
        a[0] = AnyException
      end
    end
  end

  if opts[:ignore_message] || ENV['IGNORE_MSG']
    [ result, expected ].each do | a |
      if Class === a[0]
        a[1] = :ignored_msg
      end
    end
  end

  if result != expected
    $stdout.puts <<"END"
###########################################
# ERROR:
format:   #{fmt.inspect} % #{args.inspect}
expected: #{expected.inspect}
result:   #{result.inspect}
error:    #{$error.inspect}\n  #{$error && $error.backtrace * "\n  "}
END
    pp sc
  else
    $stdout.puts <<"END"
result:   #{result.inspect}

END
  end
end

check '', nil
check 'kjasdkfj', nil

# invalid
check '%s %2$s', [ 1, 2 ]
check '%2$s %s', [ 1, 2 ]
check "%1$s %1$s", [ 1, 2 ]
check "%**s", [ ]
check "%**s", [ 1 ]
check "%***s", [ 1 ]

check "%d", [ nil ]
check "%d", [ false ]
check "%d", [ true ]

[ '%', 's', 'c', 'd', 'x', 'b', 'X', 'f', 'e', 'g', 'E', 'G', 'p' ].map do | x |
  check "%*#{x}", [ ]
  check "%*#{x}", [ 1 ]
  check "%*#{x}", [ 1, 20 ]
  check "%*#{x}", [ 1, 20, 300 ]
  check "%1.1#{x}", [ ]
  check "%1.1#{x}", [ 1 ]
  check "%1.1#{x}", [ 20 ]
end

[ '', 
  [ '%', 's', 'c', 'd', 'b', 'o', 'x', 'X', 'f', 'e', 'g', 'E', 'G', 'p' ].map do | x |
    [
     "%#{x}", 
     "%\##{x}", 
     "%1$#{x}",
     "%2$#{x}",
     "% #{x}",
     "%0#{x}",
     "%10#{x}",
     "%-10#{x}",
     "% -10#{x}",
     "%010#{x}",
     "%0-10#{x}",
     "%*#{x}",
     "%-*#{x}", 
    ]
  end,
].flatten.each do | x |
  fmt = "alks #{x} jdfa"
  bn = 12345678901234567890
  f = 23.456789
  [ 
   [ ],
   [ 42 ],
   [ -42 ],
   [ bn ],
   [ - bn ],
   [ f ],
   [ - f ],

   [ 2, 423 ], 
   [ -2, -423 ], 
   [ 2, bn ],
   [ 2, - bn ],
   [ 2, f ],
   [ 2, -f ],

   [ 20, 423 ], 
   [ -20, -423 ], 
   [ 20, bn ],
   [ 20, - bn ],
   [ 20, f ],
   [ 20, -f ],
  ].each do | args |
    check fmt, args
  end
end


