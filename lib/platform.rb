
class Platform
  # Kernel.rand(Date.today.to_s)
  @@srand ||= Kernel.rand(1 << 24)

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
    
    cmd = "/usr/bin/time #{self.cmd} #{self.opts} #{file} #{plat.name.inspect} #{result_file.inspect}"

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
      fh.puts "$platform    = ARGV[0] || 'UNKNOWN'"
      fh.puts "$result_file = ARGV[1] || (__FILE__ + '.result.rb')"
      fh.puts "$solution    = nil"
      fh.puts "n = nil"
      fh.puts "$rfh = File.open($result_file, 'w+')"
      fh.puts '$rfh.puts "["'
      fh.puts 'Kernel.at_exit { $rfh.puts "]"; $rfh.close }'
      fh.puts "begin"
      fh.puts "Kernel.srand(#{@@srand})"
      if ENV['WARMUP'] != '0'
        fh.puts '$stderr.write "warmup: "'
        render_prob fh, prob
      end
      fh.puts '$stderr.puts " GO!"'
      render_prob fh, prob, :benchmark
      fh.puts '$stderr.puts "\nFINISHED!"'
      fh.puts 'rescue Exception => err'
      fh.puts "  $rfh.puts({ :platform => $platform, 
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
          fh.puts <<"END"
  $rfh.puts({ :platform => $platform, 
              :problem => #{prob.name.inspect}, 
              :solution => $solution, 
              :n => n,
              :time => bmr.real,
             }.inspect + ', ')
   $rfh.flush
END
        end
      end
    end
    fh.puts "end" if bm
  end
end


