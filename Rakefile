

SCARLET = File.expand_path("~/local/src/scarlet/bin/scarlet")
ENV['SCARLET'] ||= SCARLET

ENV['PROBLEM'] = ENV['problem'] unless ENV['PROBLEM']

task :default do
  sh "mkdir -p problem measurement slides/image"
  ENV['MEASURE'] =
  ENV['GRAPH'] =
  ENV['SLIDES'] = '1'
  go
end

task :measure do
  ENV['MEASURE'] = '1'
  go
end

task :graph do
  ENV['GRAPH'] = '1'
  go
end

task :slides do
  ENV['SLIDES'] = '1'
  go
end

task :publish do 
  ENV['PUBLISH'] = '1'
  go
end

task :clean do
  sh "rm -rf problem measurement slides/index.html slides/image slides.textile"
end

def go
  sh "ruby ./ruby_code_tweaks.rb"
end
