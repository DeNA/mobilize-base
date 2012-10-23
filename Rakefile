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

def command?(command)
  system("type #{command} > /dev/null 2>&1")
end