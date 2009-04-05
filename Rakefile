begin
  require "rubygems"
  gem "rspec"
rescue LoadError
end
require "rake/clean"
require "spec/rake/spectask"

$stdout.sync = true

desc "Run the specs under spec/"
Spec::Rake::SpecTask.new do |t|
  t.spec_opts = %w[--colour]
  t.spec_files = FileList['spec/**/*_spec.rb']
end


namespace :parser do

  namespace :generate do
    desc 'Generate the Ruby parser to lib/irc/parser.rb (requires ragel)'
    task :ruby do
      chdir "#{File.dirname(__FILE__)}/lib/irc"
      print "Generating parser..."
      sh "ragel -R rb_parser.rl -o parser.rb"
      puts "done!"
    end

    desc 'Generate the C parser to lib/irc/ext/parser.c (requires ragel)'
    task :c do
      chdir "#{File.dirname(__FILE__)}/lib/irc/ext"
      print "Generating parser..."
      sh "ragel -C c_parser.rl -o parser.c"
      puts "done!"
    end
  end

  desc 'Compile the C parser to lib/irc/ext/parser.{bundle,so}'
  task :compile do
    chdir "#{File.dirname(__FILE__)}/lib/irc/ext"
    sh "ruby extconf.rb"
    sh "make clean"
    sh "make"
  end

  desc 'Generate and compile both the ruby and C parser (requires ragel)'
  task :all => %w[generate:ruby generate:c compile]
end

CLEAN.include("lib/irc/ext/parser.bundle", "lib/irc/ext/parser.o",
              "lib/irc/ext/Makefile")

task :default => :spec
