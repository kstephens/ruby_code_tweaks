

SCARLET = File.expand_path("~/local/src/scarlet/bin/scarlet")
ENV['SCARLET'] ||= SCARLET

task :default do
  sh "mkdir -p measurement problem slides/image"
  ENV['MEASURE'] = '1'
  ENV['GRAPH'] = '1'
  ENV['SLIDES'] = '1'
  sh "ruby ./ruby_code_tweaks.rb"
end

task :clean do
  sh "rm -rf measurement problem slides/index.html slides/image slides.textile"
end
