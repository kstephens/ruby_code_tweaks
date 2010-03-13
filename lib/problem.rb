require 'rubygems'
gem 'gruff'
require 'gruff'

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


