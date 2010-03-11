require 'rubygems'
gem 'gruff'
require 'gruff'

require 'date'
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

  attr_accessor :name, :description, :example, :n, :setup, :around, :enabled
  attr_accessor :inline
  attr_accessor :solutions, :measurements
  attr_accessor :synopsis, :notes

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

    prob = self

    $stdout.puts "\n\n==============================================================="
    $stdout.puts "Problem: #{prob.name}\n"

    platforms.each do | plat |
      plat.exec! prob
    end
    system("cat #{platforms.map{|plat| "measurement/#{prob.name}-#{plat.name}.txt"} * " "} > measurement/#{prob.name}.txt")

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

  def get_errors filter = { }
    get_measurements(filter).
      select{|h| h[:error]}
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

    prob.collect_measurements!

    max_value = measurements.map{|h| h[:time] || 0}.max

    platforms.each do | plat |
      image_file = "slides/image/#{prob.name}-#{plat.name}.png"
      $stderr.write "Creating #{image_file}..."
      errors = false
      g = Gruff::Bar.new
      g.title = "#{prob.name} on #{plat.name}" 
      g.sort = false
      
      labels = { }
      self.n.each_with_index do | n, i |
        labels[i] = (i == 0 ? "n = #{n}" : "#{n}")
      end
      solutions.each do | sol |
        data = [ ]
        self.n.each do | n |
          h = get_measurements(:n => n, :solution => sol, :platform => plat).first
          errors = true unless h
          data << (h ? h[:time] : 0)
        end
        data_name = sol.name
        if errors ||= ! get_errors(:platform => plat, :solution => sol).empty?
          data_name += " (E!)"
        end
        g.data(data_name, data)
      end
      g.data(" ", [ 0 ] * self.n.size, '#000000') if n.size > 1
      g.minimum_value = 0
      g.maximum_value = max_value
      g.labels = labels
      g.write(image_file)
      $stderr.puts "DONE"
    end

    solutions.each do | sol |
      image_file = "slides/image/#{prob.name}-sol#{sol.index}.png"
      $stderr.write "Creating #{image_file}..."

      g = Gruff::Bar.new
      g.title = "#{prob.name} using #{sol.name}" 
      g.sort = false
      
      labels = { }
      self.n.each_with_index do | n, i |
        labels[i] = (i == 0 ? "n = #{n}" : "#{n}")
      end
      platforms.each do | plat |
        errors = false
        data = [ ]
        self.n.each do | n |
          h = get_measurements(:n => n, :solution => sol, :platform => plat).first
          errors = true unless h
          data << (h ? h[:time] : 0)
        end
        data_name = plat.name
        if errors ||= ! get_errors(:platform => plat, :solution => sol).empty?
          data_name += " (E!)"
        end
        g.data(data_name, data)
      end
      g.data(" ", [ 0 ] * self.n.size, '#000000') if n.size > 1
      g.minimum_value = 0
      g.maximum_value = max_value
      g.labels = labels
      g.write(image_file)
      $stderr.puts "DONE"
    end

    self
  end
end


class Solution
  attr_accessor :name, :code, :problem, :index, :before, :example, :notes

  def initialize name, code
    @name, @code = name, code
    @before = ''
  end

  def code_block
    result = ''
    
    sol = self
    prob = problem

    prob.around =~ /\b__SOLUTION__\b([^\n]*)/
    args = $1 || ''
    
    sol_meth = "sol_#{sol.index}"
    sol_code = sol.code
    
    unless prob.inline
      result << gsub_indented(<<"END", '__SOLUTION__', sol_code)
def #{sol_meth} #{args}
  __SOLUTION__
end
END
      result << "\n"
      sol_code = "#{sol_meth}"
    end

    result << gsub_indented(prob.around, '__SOLUTION__', sol_code) 
    result << "\n"

    result
  end

  def gsub_indented template, keyword, replacement
    replacement = replacement.dup

    # Determine and remove indentation of first line from replacement.
    replacement =~ /\A(\s*)\S/
    dedent = $1 || ''
    replacement.gsub!(/^#{dedent}/, '')

    # Determine the indentation of the first line containing keyword in the template.
    template =~ /^(\s*)\b#{keyword}\b/
    indent = $1 || ''

    # Indent replacement with the indentation of the keyword.
    replacement.gsub!(/^/, indent)
    # Remove the identation in the replacement, since keyword is already indentend in the template.
    replacement.sub!(/\A#{indent}/, '')

    # Remove last newline.
    replacement.sub!(/\n\Z/, indent)
    
    # Replace keyword with replacement.
    result = template.gsub(/\b#{keyword}\b/, replacement)

    result
  end
end


class Platform
  @@instances = [ ]
  def self.instances
    @@instances
  end

  attr_accessor :name, :cmd, :opts, :enabled
  def initialize name, cmd, opts = ''
    @name, @cmd, @opts = name, cmd, opts
    @cmd = File.expand_path(@cmd)
    @@instances << self
    @enabled = File.exist?(@cmd)
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

    plat = self

    file = "problem/#{prob.name}.rb"
    result_file = "measurement/#{prob.name}-#{self.name}.rb"
    measurement_txt = "measurement/#{prob.name}-#{plat.name}.txt"
    
    cmd = "/usr/bin/time #{self.cmd} #{self.opts} #{file}"

    File.open(measurement_txt, "w+") do | fh |
      msg = "\n  #{name}: #{details}"
      $stdout.puts msg
      fh.puts msg

      msg = "  #{cmd}"
      $stdout.puts msg
      fh.puts msg
    end

    File.unlink(result_file) rescue nil
    File.open(file, "w+") do | fh |
      fh.puts "require 'benchmark'"
      fh.puts "$platform = #{plat.name.inspect}"
      fh.puts "$solution = nil"
      fh.puts "n = nil"
      fh.puts "$rfh = File.open(#{result_file.inspect}, 'w+')"
      fh.puts '$rfh.puts "["'
      fh.puts 'Kernel.at_exit { $rfh.puts "]"; $rfh.close }'
      fh.puts "begin"
      fh.puts "Kernel.srand(#{$srand})"
      if ENV['WARMUP'] != '0'
        fh.puts '$stderr.write "warmup: "'
        render_prob fh, prob
      end
      fh.puts '$stderr.puts " GO!"'
      render_prob fh, prob, :benchmark
      fh.puts '$stderr.puts "\nFINISHED!"'
      fh.puts 'rescue Exception => err'
      fh.puts "  $rfh.puts({ :platform => #{plat.name.inspect}, 
                             :problem => #{prob.name.inspect}, 
                             :solution => $solution, 
                             :n => n, 
                             :error => err.to_s, 
                             :backtrace => err.backtrace }.inspect + ', ')" 
      fh.puts 'end'
      fh.puts 'exit 0'
      fh.flush
    end
    # system("cat #{file}")

    cmd = "( #{cmd} ) 2>&1 | tee -a #{measurement_txt}"
    unless result = system(cmd)
      data = File.read(result_file) rescue nil
      data ||= '[ ]'
      data = Kernel.eval(data) || [ ]
      data << { :platform => plat.name, :error => "#{cmd} failed", :result => result.to_s }
      File.open(result_file, "w+") do | fh |
        fh.puts(data.inspect)
      end
    end
    self
  end

  def render_prob fh, prob, bm = false
    plat = self
    fh.puts "Benchmark.bm(40) do | bm |" if bm
    prob.n.each do | n |
      fh.puts "n = #{n}"
      fh.puts '  $stderr.write n' unless bm
      fh.puts prob.setup
      prob.solutions.each do | sol |
        fh.puts "  $solution = #{sol.name.inspect}"

        fh.puts sol.before

        fh.puts "  ObjectSpace.garbage_collect"
        if bm
          fh.puts "  bmr = bm.report('n = #{'%7d' % n} : ' + #{sol.name.to_s.inspect}) do"
        else
          fh.puts '  $stderr.write "."'
        end

        fh.puts sol.code_block

        if bm
          fh.puts '  end' 
          fh.puts "  $rfh.puts({ :platform => #{plat.name.inspect}, :problem => #{prob.name.inspect}, :solution => $solution, :n => n, :time => bmr.real }.inspect + ', ')"
          fh.puts "  $rfh.flush"
        end
      end
    end
    fh.puts "end" if bm
  end
end


########################################################

#Platform.new("MRI-1.8.6-p287",   "~/local/ruby/1.8.6-p287/bin/ruby")
Platform.new("MRI-1.8.6-p399",   "~/local/ruby/1.8.6-p399/bin/ruby")
Platform.new("MRI-1.8.7", "/usr/bin/ruby")
Platform.new("MRI-1.9",   "~/local/ruby/trunk/bin/ruby")
#Platform.new("JRuby-1.2", "/usr/bin/jruby1.2")
Platform.new("JRuby-1.4", "~/local/jruby-1.4.0/bin/jruby", '--fast')
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

s = p.solution "String#%", <<'END'
  "%s, %d" % [ foobar, n ]
END

s = p.solution "String interpolation", <<'END'
  "#{foobar}, #{n}"
END

p.synopsis = <<'END'
* String interpolation is faster.
* Rubinius String#% is very slow.
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
