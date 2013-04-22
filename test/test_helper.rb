require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'
require 'redis/namespace'

$dir = File.dirname(File.expand_path(__FILE__))
#set test environment
ENV['MOBILIZE_ENV'] = 'test'
require 'mobilize-base'
$TESTING = true
module TestHelper
  def TestHelper.wait_for_stages(time_limit=600,stage_limit=120,wait_length=10)
    time = 0
    time_since_stage = 0
    #check for 10 min
    while time < time_limit and time_since_stage < stage_limit
      sleep wait_length
      job_classes = Mobilize::Resque.jobs.map{|j| j['class']}
      if job_classes.include?("Mobilize::Stage")
        time_since_stage = 0
        puts "saw stage at #{time.to_s} seconds"
      else
        time_since_stage += wait_length
        puts "#{time_since_stage.to_s} seconds since stage seen"
      end
      time += wait_length
      puts "total wait time #{time.to_s} seconds"
    end

    if time >= time_limit
      raise "Timed out before stage completion"
    end
  end

  #test methods
  def TestHelper.restart_test_redis
    TestHelper.stop_test_redis
    if !system("which redis-server")
      raise "** can't find `redis-server` in your path, you need redis to run Resque and Mobilize"
    end
    "redis-server #{Mobilize::Base.root}/test/redis-test.conf".bash
  end

  def TestHelper.stop_test_redis
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    puts "removing redis db dump file"
    sleep 5
    `rm -f #{Mobilize::Base.root}/test/dump.rdb #{Mobilize::Base.root}/test/dump-cluster.rdb`
  end

  def TestHelper.set_test_env
    ENV['MOBILIZE_ENV']='test'
    ::Resque.redis="localhost:9736"
    mongoid_config_path = "#{Mobilize::Base.root}/config/mobilize/mongoid.yml"
    Mongoid.load!(mongoid_config_path, Mobilize::Base.env)
  end

  def TestHelper.drop_test_db
    TestHelper.set_test_env
    Mongoid.session(:default).collections.each do |collection| 
      unless collection.name =~ /^system\./
        collection.drop
      end
    end
  end

  def TestHelper.build_test_runner(user_name)
    TestHelper.set_test_env
    u = Mobilize::User.where(:name=>user_name).first
    Mobilize::Jobtracker.update_status("delete old books and datasets")
    # delete any old runner from previous test runs
    gdrive_slot = Mobilize::Gdrive.owner_email
    u.runner.gsheet(gdrive_slot).spreadsheet.delete
    Mobilize::Dataset.find_by_handler_and_path('gbook',u.runner.title).delete
    Mobilize::Jobtracker.update_status("enqueue jobtracker, wait 45s")
    Mobilize::Jobtracker.start
    sleep 45
  end

  def TestHelper.owner_user
    gdrive_slot = Mobilize::Gdrive.owner_email
    puts "create user 'mobilize'"
    user_name = gdrive_slot.split("@").first
    return Mobilize::User.find_or_create_by_name(user_name)
  end
end
