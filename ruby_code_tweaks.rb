require 'rubygems'
gem 'gruff'
require 'gruff'

require 'erb'
require 'pp'
require 'tempfile'

# Kernel.rand(Date.today.to_s)
$srand = Kernel.rand(1 << 24)

class Problem
  @@instances = [ ]
  def self.instances
    @@instances
  end

  attr_accessor :name, :description, :example, :n, :scenario, :setup, :around, :enabled
  attr_accessor :solutions, :measurements
  attr_accessor :synopsis

  def initialize name
    @name = name
    @n = [ 100000 ]
    @measurements = [ ]
    @solutions = [ ]
    @setup = ''
    @around = '__SOLUTION__'
    @enabled = (ENV['ENABLED'] || 1).to_i != 0
    @@instances << self
  end

  def solution name, code
    sol = Solution.new(name, code)
    @solutions << sol 
    sol.index = @solutions.size
    sol.problem = self
    sol
  end

  def measure!
    return self unless @enabled

    $stdout.puts "\n\n==============================================================="
    $stdout.puts "Problem: #{self.name}"
    Platform.instances.each do | x |
      x.exec! self
    end

    self
  end

  def platforms
    Platform.instances
  end


  def collect_measurements!
    prob = self

    @normalized_measuments = nil
    @measurements = [ ]
    Dir["measurement/#{prob.name}-*.rb"].sort.each do | result_file |
      $stderr.puts "Reading #{result_file}"
      results = Kernel.eval(File.read(result_file))
      prob.measurements.concat results if results
    end
    self
  end

  def normalized_measurements
    @normalized_measurements ||= measurements.map do |h|
      h = h.dup
      h[:solution] = solutions.find{|x| x.name == h[:solution]}
      h[:platform] = platforms.find{|x| x.name == h[:platform]}
      h
    end
  end

  def get_measurements filter = { }
    normalized_measurements.select do |h|
      ((f = filter[:n]) ? f == h[:n] : true) &&
      ((f = filter[:solution]) ? f == h[:solution] : true) &&
      ((f = filter[:platform]) ? f == h[:platform] : true)
    end
  end

  def best_solution
    sc = { } # solution score
    platforms.each do | plat |
      st = { } # solution time per platform.
      get_measurements(:platform => plat).each do | h |
        sol = h[:solution]
        st[sol] ||= 0
        st[sol] += h[:time]
      end
      best_solution = solutions.find{|sol| st[sol] == st.values.min}
      sc[best_solution] ||= 0
      sc[best_solution] += 1
    end
    best_solution = solutions.find{|sol| sc[sol] == sc.values.max}
    best_solution
  end

  def graph!
    return self unless @enabled

    prob = self

    max_value = measurements.map{|h| h[:time]}.max

    platforms.each do | plat |
      g = Gruff::Bar.new
      g.title = "#{prob.name} on #{plat.name}" 
      g.sort = false
      
      labels = { }
      self.n.each_with_index do | n, i |
        labels[i] = "n=#{n}"
      end
      solutions.each do | sol |
        data = [ ]
        self.n.each do | n |
          h = get_measurements(:n => n, :solution => sol, :platform => plat).first
          data << (h ? h[:time] : 0)
        end
        g.data(sol.name, data)
      end
      g.data(" ", [ 0 ] * self.n.size, '#000000') if n.size > 1
      g.minimum_value = 0
      g.maximum_value = max_value
      g.labels = labels
      g.write(file = "slides/image/#{prob.name}-#{plat.name}.png")
      $stderr.puts "Created #{file}"
    end

    solutions.each do | sol |
      g = Gruff::Bar.new
      g.title = "#{prob.name} using #{sol.name}" 
      g.sort = false
      
      labels = { }
      self.n.each_with_index do | n, i |
        labels[i] = "n=#{n}"
      end
      platforms.each do | plat |
        data = [ ]
        self.n.each do | n |
          h = get_measurements(:n => n, :solution => sol, :platform => plat).first
          data << (h ? h[:time] : 0)
        end
        g.data(plat.name, data)
      end
      g.data(" ", [ 0 ] * self.n.size, '#000000') if n.size > 1
      g.minimum_value = 0
      g.maximum_value = max_value
      g.labels = labels
      g.write(file = "slides/image/#{prob.name}-sol#{sol.index}.png")
      $stderr.puts "Created #{file}"
    end

    self
  end
end


class Solution
  attr_accessor :name, :code, :problem, :index, :before, :example

  def initialize name, code
    @name, @code = name, code
    @before = ''
  end
end


class Platform
  @@instances = [ ]
  def self.instances
    @@instances
  end

  attr_accessor :name, :cmd, :enabled
  def initialize name, cmd
    @name, @cmd = name, cmd
    @@instances << self
    @enabled = true
  end

  def details
    @details ||=
      `#{cmd} -v`.chomp.freeze
  end

  def exec! x, *args
    send("exec_#{x.class.name}!", x, *args);
  end

  def exec_Problem! prob
    return unless self.enabled
    $stdout.puts "\n  #{name}: #{details}"
    file = "problem/#{prob.name}.rb"
    result_file = "measurement/#{prob.name}-#{self.name}.rb"
    File.open(file, "w+") do | fh |
      fh.puts "require 'benchmark'"
      fh.puts "$rfh = File.open(#{result_file.inspect}, 'w+')"
      fh.puts '$rfh.puts "["'
      fh.puts 'Kernel.at_exit { $rfh.puts "]"; $rfh.close }'
      fh.puts "Kernel.srand(#{$srand})"
      fh.puts '$stderr.write "warmup: "'
      render_prob fh, prob
      fh.puts '$stderr.puts " GO!"'
      render_prob fh, prob, :benchmark
      fh.puts '$stderr.puts "FINISHED!"'
      fh.puts 'exit 0'
      fh.flush
    end
    # system("cat #{file}")
    cmd = "/usr/bin/time #{self.cmd} #{file}"
    $stdout.puts "  #{cmd}"
    system(cmd)
    self
  end

  def render_prob fh, prob, bm = false
    plat = self
    fh.puts "Benchmark.bm(40) do | bm |" if bm
    prob.n.each do | n |
      fh.puts "n = #{n}"
      fh.puts '  $stderr.write n' unless bm
      fh.puts prob.setup.sub('__SCENARIO__', prob.scenario || '')
      prob.solutions.each do | sol |
        code = prob.around.sub('__SOLUTION__', sol.code)
        fh.puts sol.before
        fh.puts "  ObjectSpace.garbage_collect"
        if bm
          fh.puts "  bmr = bm.report('n = #{'%7d' % n} : ' + #{sol.name.to_s.inspect}) do"
        else
          fh.puts '  $stderr.write "."'
        end
        fh.puts code
        if bm
          fh.puts '  end' 
          fh.puts "  $rfh.puts({ :platform => #{plat.name.inspect}, :problem => #{prob.name.inspect}, :solution => #{sol.name.inspect}, :n => n, :time => bmr.real }.inspect + ', ')"
        end
      end
    end
    fh.puts "end" if bm
  end
end


Platform.new("MRI-1.8.6-p287",   "~/local/ruby/1.8.6-p287/bin/ruby")
Platform.new("MRI-1.8.6-p399",   "~/local/ruby/1.8.6-p399/bin/ruby")
Platform.new("MRI-1.8.7", "/usr/bin/ruby")
Platform.new("MRI-1.9",   "~/local/ruby/trunk/bin/ruby")
Platform.new("JRuby-1.2", "/usr/bin/jruby1.2")
Platform.new("Rubinius", "~/local/rubinius/trunk/bin/rbx")

########################################################

if false
p = Problem.new(:null)
  
p.solution "nothing", <<END
  n
END
end

########################################################

p = Problem.new(:do_n_times)
p.description = "Yield to a block N times."
p.n = [ 1000 ]
p.around= <<END
  40000.times do
    __SOLUTION__
  end
END

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
* Use n.times, for portability do not bother with the rest.
END

############################################################

p = Problem.new(:tail_position_return)
p.description = 'Return a value from a method.'
p.enabled = true
p.n = [ 10_000_000 ]
p.around = <<END
  n.times do
    __SOLUTION__
  end
END

s = p.solution "explicit return", <<'END'
  explicit_return true
  explicit_return false
END
s.before = <<'END'
def explicit_return x
  if x
    return 1
  else
    return 2
  end
end
END

s = p.solution "fall through", <<'END'
  fall_through true
  fall_through false
END
s.before = <<'END'
def fall_through x
  if x
    1
  else
    2
  end
end   
END

p.synopsis = <<'END'
* Newer ruby implementations recognize tail position returns.
* No return keyword == less code.
* Easier to debug and move expressions around later.
END

############################################################

p = Problem.new(:string_concatenation)
p.description = <<'END'
Accumulate String parts into one larger String.
END
# p.enabled = false
p.n = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 50, 100, 200, 500, 1000 ]
p.scenario = '(0 ... 100).to_a.map{"a" * n}'
p.setup= <<'END'
  @try ||= { }
  @try[n] ||= __SCENARIO__
END
p.around= <<END
  @str = ''
  100.times do
    @try[n].each do | x |
      __SOLUTION__
    end
  end
END

p.solution "str += x", <<END
  @str += x
END
p.solution "str << x", <<END
  @str << x
END

p.synopsis = <<'END'
* Use str << x
* str += x creates pointless garbage
* Use array.concat x, instead of array += x
END


############################################################

p = Problem.new(:array_inclusion_short)
p.description = 'Is a value in a short, constant list?'
p.example = <<'END'
x == :foo || x == :bar

[ :foo, :bar ].include?(x)

case x
when :foo, :bar
  true
end
END

p.n= [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
p.setup= <<END
  @array = (0 ... n).to_a.sort_by{|x| rand}
  @try   = (0 ... 1000).to_a.map{|x| rand(n + n)}.sort_by{|x| rand}
END
p.around= <<'END'
  1000.times do
    @try.each do | x |
      __SOLUTION__
    end
  end
END

s = p.solution "array.include?(x)", <<END
  array_include?(x)
END
s.example = <<'END'
  ARRAY = [ 0, 1 ].freeze   # n == 2
  ..
  ARRAY.include?(x)
END
s.before = <<'END'
def array_include? x
  @array.include? x
end
END

s = p.solution "[ ... ].include?(x)", <<END
  inline_array_include?(x)
END
s.example = <<'END'
  [ 0, 1 ].include?(x)   # n == 2
END
s.before = <<'END'
eval <<"RUBY"
  def inline_array_include? x
    #{@array.inspect}.include?(x)
  end
RUBY
END

s = p.solution "x == y1 || ...", <<END
  expr?(x)
END
s.before = <<'END'
eval <<"RUBY"
  def expr? x
    #{@array.map{|y| "x == #{y.inspect}"} * " || "}
  end
RUBY
END
s.example = <<'END'
  x == 0              # n == 1
  x == 0 || x == 1    # n == 2
END

s = p.solution "case x; when y1, y2 ...", <<END
  case_when?(x)
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
  case_when_splat?(x)
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
  hash_key?(x)
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
  hash_get x
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
  set_include?(x)
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
* Use x == y when n == 1.
* Use hash.key?(x) when n > 1.
END

############################################################

p = Problem.new(:array_inclusion)
p.n= [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 50, 100, 200, 500, 1000 ]
p.setup= <<END
  @array = (0 ... n).to_a.sort_by{|x| rand}
  @try   = (0 ... 2000).to_a.sort_by{|x| rand}
END
p.around= <<END
  100.times do
    @try.each do | x |
      __SOLUTION__
    end
  end
END

p.solution "Array#include?", <<END
  @array.include?(x)
END
p.solution "case x; when *array", <<END
  case x
  when *@array
    true
  end
END
p.solution "! (array & [ x ]).empty?", <<END
  ! (@array & [ x ]).empty?
END

=begin
* If a & b is implemented as:
a.each do | ae |
  b.each do | be |
    result << be if ae == be
  end
end

1) Swap a, b if a.size > b.size
2) Stop when result.size == [ a.size, b.size ].min
=end


############################################################

p = Problem.new(:set_intersection)
p.description = 'Produce the interection of two unique arrays.'
p.n = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, ] #, 50 ]
p.setup= <<'END'
  @array = (0 ... n).to_a.sort_by { | x | rand }
  @try   = (0 ... n * 2).to_a.map { | i | (0 ... i).to_a.sort_by { | x | rand } }
END
p.around= <<END
  100.times do
    __SOLUTION__
  end
END

s = p.solution "simple", <<END
  @try.each do | b |
    simple @array, b
    simple b, @array
  end
END
s.before = <<'END'
def simple a, b
  result = [ ]
  a.each do | ae |
    b.each do | be |
      if ae == be
        result << be 
      end
    end
  end
  result
end
END

s = p.solution "swap on size", <<END
  @try.each do | b |
    simple_with_swap @array, b
    simple_with_swap b, @array
  end
END
s.before = <<'END'
def simple_with_swap a, b
  b, a = a, b if a.size > b.size
  result = [ ]
  a.each do | ae |
    b.each do | be |
      if ae == be
        result << be 
      end
    end
  end
  result
end
END

s = p.solution "swap on size and limit", <<END
  @try.each do | b |
    simple_with_swap @array, b
    simple_with_swap b, @array
  end
END
s.before = <<'END'
def simple_with_swap_and_limit a, b
  b, a = a, b if a.size > b.size
  max_result_size = [ a.size, b.size ].min
  result = [ ]
  a.each do | ae |
    b.each do | be |
      if ae == be 
        result << be
        return result if result.size >= max_result_size
      end
    end
  end
  result
end
END


############################################################

if ENV['MEASURE'] == "1"
  Dir['measurement/*.rb'].each{|fn| File.unlink fn } 
end

Problem.instances.each do | prob |
  prob.measure! if ENV['MEASURE'] == "1"
  prob.collect_measurements!
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
  system "set -x; cp image/*.* slides/image"
  system "set -x; tar -zcvf sildes.tar.gz slides"
end
