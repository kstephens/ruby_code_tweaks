#!/usr/bin/env ruby

$: << File.dirname(__FILE__) + "/lib"

require 'problem'
require 'solution'
require 'platform'

require 'date'
require 'erb'
require 'pp'
require 'tempfile'

########################################################

#Platform.new("MRI-1.8.6-p287",   "~/local/ruby/1.8.6-p287/bin/ruby")
Platform.new("MRI-1.8.6-p399",   "~/local/ruby/1.8.6-p399/bin/ruby")
#Platform.new("MRI-1.8.7", "/usr/bin/ruby")
Platform.new("MRI-1.8.7", "~/local/ruby/1.8.7-git/bin/ruby")
Platform.new("MRI-1.9",   "~/local/ruby/trunk/bin/ruby")
#Platform.new("JRuby-1.2", "/usr/bin/jruby1.2")
Platform.new("JRuby-1.4", "~/local/jruby-1.4.0/bin/jruby", '--fast')
Platform.new("Rubinius-ks", "~/local/rubinius/kstephens/bin/rbx")
Platform.new("Rubinius", "~/local/rubinius/trunk/bin/rbx")

########################################################
# Begin problems.
########################################################

p = Problem.new(:yield_n_times)
p.description = "Yield to a block N times."
p.n = [ 1000 ]
p.around= <<END
  40000.times do
    __SOLUTION__
  end
END
p.inline = true

p.solution "for i in 1..n", <<END
  for i in 1..n do
    n
  end
END

p.solution "n.times", <<END
  n.times do
    n
  end
END

p.solution "1.upto(n)", <<END
  1.upto(n) do
    n
  end
END

p.solution "(1..n).each", <<END
  (1..n).each do
    n
  end
END

p.synopsis = <<END
* Use n.times, for portability.
* Do not bother with the rest.
* Ranges create garbage.
* Something is up with MRI 1.8.7.
END

############################################################

p = Problem.new(:tail_position_return)
p.description = 'Return a value from a method.'
p.n = [ 10_000_000 ]
p.around = <<END
  n.times do
    x = true
    __SOLUTION__ x
    x = false
    __SOLUTION__ x
  end
END

s = p.solution "explicit return", <<'END'
  if x
    return 1
  else
    return 2
  end
END

s = p.solution "fall through", <<'END'
  if x
    1
  else
    2
  end
END

p.synopsis = <<'END'
* Newer ruby implementations recognize tail position returns.
* No return keyword == less code.
* Easier to debug and move expressions around later.
END

############################################################

p = Problem.new(:string_formatting)
p.description = 'Format a String'
p.n = [ 1_000_000 ]
p.setup = <<'END'
  foobar = "foobar"
END
p.around = <<END
  n.times do
    __SOLUTION__
  end
END
p.inline = true

s = p.solution "String#%", <<'END'
  "%s, %d" % [ foobar, n ]
END

s = p.solution "String interpolation", <<'END'
  "#{foobar}, #{n}"
END

s = p.solution "SprintfCompiler", <<'END'
  SprintfCompiler.format("%s, %d", [ foobar, n ])
END
s.before = <<'END'
require 'sprintf_compiler'
END

p.synopsis = <<'END'
* String interpolation is faster.
* Rubinius String#% is slow.
* SprintfCompiler speeds up Rubinius for common formats.
END

############################################################

p = Problem.new(:string_to_symbol)
p.description = 'Construct a Symbol from a String.'
p.n = [ 10_000_000 ]
p.setup = <<'END'
  foobar = "foobar"
END
p.around = <<END
  n.times do
    __SOLUTION__
  end
END
p.inline = true

s = p.solution "String#to_sym", <<'END'
  (foobar + "123").to_sym
END

s = p.solution "Dynamic Symbol", <<'END'
  :"#{foobar}123"
END

p.synopsis = <<'END'
* :"symbol" is faster on all except MRI 1.9.
END

############################################################

p = Problem.new(:inject)
p.description = 'Enumerate elements while using a temporary or block variable.'
p.n = [ 1, 10, 20, 50, 100, 200 ]
p.setup = <<END
  array = (0 ... n).to_a.sort_by{|x| rand}
END
p.around = <<END
  100000.times do
    __SOLUTION__
  end
END
p.inline = true

s = p.solution "Array#inject", <<END
  array.inject({ }) { | hash, x | hash[x] = true; hash }
END

s = p.solution "Local variable", <<END
  hash = { }
  array.each { | x | hash[x] = true }
  hash
END

p.synopsis = <<'END'
* Use a local variable, #inject is slower.
* Rubinius appears to have a problem.
END

############################################################

p = Problem.new(:string_concatenation)
p.description = <<'END'
Accumulate String parts of size N into one larger String.
END
# p.enabled = false
p.n = [ 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000 ]
p.setup= <<'END'
  parts = (0 ... 100).to_a.map{"a" * n}
END
p.around= <<END
  str = ''
  100.times do
    __SOLUTION__
  end
END
p.inline = true

s = p.solution "str += x", <<END
  parts.each do | x |
    str += x
  end
END
s.notes = <<'END'
@@@ ruby
  str += x
@@@
is the same as:
@@@ ruby
  str = (str + x)
@@@
END

s = p.solution "str << x", <<'END'
  parts.each do | x |
    str << x
  end
END
s.notes = <<'END'
END

s = p.solution "parts.join", <<END
  str << parts.join("")
END
s.notes = <<'END'
END


p.synopsis = <<'END'
* Use str << x
* str += x creates pointless garbage.
* Some platforms handle garbage and assignments poorly.
* Use array.concat x, instead of array += x.
END


############################################################

p = Problem.new(:array_include_short)
p.description = 'Is a value in a short, constant set?'
p.n= [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
p.example = <<'END'
  x == 0 || x == 1

  [ 0, 1 ].include?(x)

  case x
  when 0, 1
    true
  end
END
p.inline = true
p.setup= <<END
  @array = (0 ... n).to_a.sort_by{|x| rand}
  try    = (0 ... 1000).to_a.map{|x| rand(n + n)}.sort_by{|x| rand}
END
p.around= <<'END'
  1000.times do
    try.each do | x |
      __SOLUTION__ x
    end
  end
END

s = p.solution "x == y1 || ...", <<'END'
  inline_any_equal?
END
s.before = <<'END'
eval <<"RUBY"
  def inline_any_equal? x
    #{@array.map{|y| "x == #{y.inspect}"} * " || "}
  end
RUBY
END
s.example = <<'END'
  x == 0                 # n == 1
  x == 0 || x == 1       # n == 2
  ...
END

s = p.solution "[ ... ].include?(x)", <<END
  inline_array_include?
END
s.example = <<'END'
  [ 0, 1 ].include?(x)     # n == 2
END
s.before = <<'END'
eval <<"RUBY"
  def inline_array_include? x
    #{@array.inspect}.include?(x)
  end
RUBY
END

s = p.solution "array.include?(x)", <<END
  array_include?
END
s.example = <<'END'
  ARRAY = [ 0, 1 ].freeze   # n == 2
  ...
  ARRAY.include?(x)
END
s.before = <<'END'
  def array_include? x
    @array.include? x
  end
END

s = p.solution "case x; when y1, y2 ...", <<END
  case_when?
END
s.example = <<'END'
  case x
  when 0, 1           # n == 2
    true
  end
END
s.before = <<'END'
eval(expr = <<"RUBY"); # $stderr.puts expr
  def case_when? x
    case x
    when #{@array * ', '}
      true
    end
  end
RUBY
END

s = p.solution "case x; when *array", <<END
  case_when_splat?
END
s.example = <<'END'
  ARRAY = [ 0, 1 ].freeze
  ...
  case x
  when *ARRAY
    true
  end
END
s.before = <<'END'
  def case_when_splat? x
    case x
    when *@array
      true
    end
  end
END

s = p.solution "hash.key?(x)", <<END
  hash_key?
END
s.example = <<'END'
  HASH = { 0 => true, 1 => true }.freeze
  ...
  HASH.key?(x)
END
s.before = <<'END'
@hash = { }
@array.each{|x| @hash[x] = true}
def hash_key? x
  @hash.key? x
end
END

s = p.solution "hash[x]", <<END
  hash_get
END
s.example = <<'END'
  HASH = { 0 => true, 1 => true }.freeze
  ...
  HASH[x]
END
s.before = <<'END'
@hash = { }
@array.each{|x| @hash[x] = true}
def hash_get x
  @hash[x]
end
END

s = p.solution "set.include?(x)", <<END
  set_include?
END
s.example = <<'END'
require 'set'
SET = Set.new([ 0, 1 ])   # n == 2
...
SET.include? x
END
s.before = <<'END'
require 'set'
@set = Set.new(@array)
def set_include? x
  @set.include? x
end
END

p.synopsis = <<'END'
* Beware: case uses #===, not #==.
* Use x == y when n == 1.
* Use hash.key?(x) when n > 1.
* x == y1 && ... is faster than [ ... ].include?(x) up until n == 10.
* Ruby Set is slower than Hash.
END

############################################################

p = Problem.new(:array_include)
p.n= [ 1, 10, 20, 50, 100, 200, 500, 1000 ]
p.setup= <<END
  array = (0 ... n).to_a.sort_by{|x| rand}
  try   = (0 ... 2000).to_a.sort_by{|x| rand}
END
p.around= <<END
  100.times do
    try.each do | x |
      __SOLUTION__
    end
  end
END
p.inline = true

s = p.solution "Array#include?", <<END
  array.include?(x)
END

s = p.solution "case x; when *array", <<END
  case x
  when *array
    true
  end
END

s = p.solution "! (array & [ x ]).empty?", <<END
  ! (array & [ x ]).empty?
END

s = p.solution "hash.key?(x)", <<END
  hash.key?(x)
END
s.before = <<'END'
  hash = { }; array.each { | x | hash[x] = true }
END
 
p.synopsis = <<'END'
* Set performs poorly on Rubinius.
* Set performs "too well" on everything else.
* Use a Hash.
END

############################################################

############################################################

f = (ENV['PROBLEM'] || '').split(/,|\s+/)
# $stderr.puts "PROBLEM = #{f.inspect}"
Problem.instances.select do | prob |
  f.empty? ? true : f.include?(prob.name.to_s)
end.each do | prob |
  prob.measure! if ENV['MEASURE'] == "1"
  prob.graph! if ENV['GRAPH'] == "1"
end

############################################################

if ENV['SLIDES'] == '1'
  slides_textile = 'slides.textile'
  erb = ERB.new(File.read(erb_file = "#{slides_textile}.erb"))
  erb.filename = erb_file
  File.open(slides_textile, "w+") { | out | out.puts erb.result(binding) }
  $stderr.puts "Created #{slides_textile}"
  SCARLET = (ENV['SCARLET'] ||= File.expand_path("~/local/src/scarlet/bin/scarlet"))
  # system "#{SCARLET} -g slides -f html slides.textile"
  system "set -x; #{SCARLET} -f html slides.textile > slides/index.html"
  system "set -x; cp -p image/*.* slides/image"
  system "rm -rf slides/problem; set -x; cp -rp problem slides/problem"
  system "rm -rf slides/measurement; set -x; cp -rp measurement slides/measurement; rm -f slides/measurement/*.rbc"
  system "rm -rf ruby_code_tweaks-slides; set -x; cp -rp slides ruby_code_tweaks-slides"
  system "set -x; tar -zcvf ruby_code_tweaks-slides.tar.gz ruby_code_tweaks-slides"
end

if ENV['PUBLISH'] == '1'
  system "rsync -aruzv slides kscom:~/kurtstephens.com/priv/ruby/ruby_code_tweaks/"
end
