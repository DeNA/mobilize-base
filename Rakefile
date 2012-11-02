require 'rubygems'

begin
  require 'bundler/setup'
rescue LoadError => e
  warn e.message
  warn "Run `gem install bundler` to install Bundler"
  exit -1
end

#
# Bundler
#
require "bundler/gem_tasks"

#
# Setup
#
$LOAD_PATH.unshift 'lib'
require 'mobilize-base/tasks'


#
# Tests
#
require 'rake/testtask'

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/*_test.rb']
end
task :default => :test
