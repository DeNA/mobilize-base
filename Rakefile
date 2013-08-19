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
task :default => [:spec]
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec) do |spec|
    spec.rspec_opts = %w[-cfs -r ./spec/spec_helper.rb]
  end
rescue LoadError => e
end
