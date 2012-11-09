require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'
require 'redis/namespace'

$dir = File.dirname(File.expand_path(__FILE__))
#set test environment
ENV['MOBILIZE_ENV'] = 'test'
require 'mobilize-base'
$TESTING = true

#
# make sure we can run redis
#

if !system("which redis-server")
  puts '', "** can't find `redis-server` in your path, you need redis to run Resque and Mobilize"
  abort ''
end

#start test redis
puts "Starting redis for testing at 127.0.0.1:#{Mobilize::Resque.config['redis_port']}..."
`redis-server #{$dir}/redis-test.conf`
Resque.redis = "127.0.0.1:#{Mobilize::Resque.config['redis_port']}"
