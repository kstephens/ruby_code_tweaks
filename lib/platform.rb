
class Platform
  @@instances = [ ]
  def self.instances
    @@instances
  end
  def self.instances_enabled
    instances.select{|x| x.enabled }
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

    file = prob.problem_file
    result_file = prob.measurement_file(self)
    output_txt = prob.output_file(self)

    cmd_line = "#{self.cmd} #{self.opts}"
    cmd = "/usr/bin/time #{cmd_line} #{file} #{plat.name.inspect} #{result_file.inspect}"

    unless ENV['FORCE']
      if File.exist?(ouput_txt)
        $stdout.puts "#{output_txt} already exists, use FORCE=1 to force"
        return self
      end
    end

    File.open(output_txt, "w+") do | fh |
      msg = "\n  #{name}: #{details}"
      $stdout.puts msg
      fh.puts msg

      msg = "  #{cmd}"
      $stdout.puts msg
      fh.puts msg
    end

    File.unlink(result_file) rescue nil
    prob.render file

    # system("cat #{file}")

    cmd = "( export RCT_PLATFORM_CMD_LINE=#{cmd_line.inspect}; #{cmd} ) 2>&1 | tee -a #{output_txt}"
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

  rescue Exception => err
    File.unlink(result_file) rescue nil
    File.unlink(measurement_txt) rescue nil

    self
  end

  def render_prob fh, prob, bm = false
    prob.render_prob fh, bm
  end
end


