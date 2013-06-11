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
  def TestHelper.confirm_expected_jobs(expected_fixture_name,time_limit=600)
    #clear all failures
    Mobilize::Resque.failures.each{|f| f.delete}
    jobs = {}
    jobs['expected'] = TestHelper.load_fixture(expected_fixture_name)
    jobs['pending'] = jobs['expected'].select{|j| j['confirmed_ats'].length < j['count']}
    start_time = Time.now.utc
    total_time = 0
    while (jobs['pending'].length>0 or #while there are pending jobs
           #or there are workers working (don't count jobtracker)
           Mobilize::Resque.workers('working').select{|w| w.job['payload']['class']!='Mobilize::Jobtracker'}.length>0) and
           total_time < time_limit #time limit not yet expired
      #working jobs are running on the queue at this instant
      jobs['working'] = Mobilize::Resque.workers('working').map{|w| w.job}.select{|j| j and j['payload'] and j['payload']['args']}
      #failed jobs are in the failure queue
      jobs['failed'] = Mobilize::Resque.failures.select{|j| j and j['payload'] and j['payload']['args']}

      #unexpected jobs are not supposed to be run in this test, includes leftover failures
      jobs['unexpected'] = {}
      error_msg = ""
      ['working','failed'].each do |state|
        jobs['unexpected'][state] = jobs[state].reject{|j|
                                      jobs['expected'].select{|ej|
                                        ej['state']==state and j['payload']['args'].first == ej['path']}.first}
        if jobs['unexpected'][state].length>0
          error_msg += state + ": " + jobs['unexpected'][state].map{|j| j['payload']['args'].first}.join(";") + "\n"
        end
      end
      #clear out unexpected paths or there will be failure
      if error_msg.length>0
        raise "Found unexpected results:\n" + error_msg
      end

      #now make sure pending jobs get done
      jobs['expected'].each do |j|
        start_confirmed_ats = j['confirmed_ats']
        resque_timestamps = jobs[j['state']].select{|sj| sj['payload']['args'].first == j['path']}.map{|sj| sj['run_at'] || sj['failed_at']}
        new_timestamps = (resque_timestamps - start_confirmed_ats).uniq
        if new_timestamps.length>0 and j['confirmed_ats'].length < j['count']
          j['confirmed_ats'] += new_timestamps
          puts "#{Time.now.utc.to_s}: #{new_timestamps.length.to_s} #{j['state']} added to #{j['path']}; total #{j['confirmed_ats'].length.to_s} of #{j['count']}"
        end
      end

      #figure out who's still pending
      jobs['pending'] = jobs['expected'].select{|j| j['confirmed_ats'].length < j['count']}
      sleep 1
      total_time = Time.now.utc - start_time
      puts "#{total_time.to_s} seconds elapsed" if total_time.to_s.ends_with?("0")
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
    user_name = gdrive_slot.split("@").first
    return Mobilize::User.find_or_create_by_name(user_name)
  end

  def TestHelper.load_fixture(name)
    #assume yml, check
    yml_file_path = "#{Mobilize::Base.root}/test/fixtures/#{name}.yml"
    standard_file_path = "#{Mobilize::Base.root}/test/fixtures/#{name}"
    if File.exists?(yml_file_path)
      YAML.load_file(yml_file_path)
    elsif File.exists?(standard_file_path)
      File.read(standard_file_path)
    else
      raise "Could not find #{standard_file_path}"
    end
  end

  def TestHelper.write_fixture(fixture_name, target_url, options={})
    u = TestHelper.owner_user
    fixture_raw = TestHelper.load_fixture(fixture_name)
    if options['replace']
      fixture_data = if fixture_raw.class == Array
                     fixture_raw.hash_array_to_tsv
                   elsif fixture_raw.class == String
                     fixture_raw
                   end
      Mobilize::Dataset.write_by_url(target_url,fixture_data,u.name,u.email)
    elsif options['update']
      handler, sheet_path = target_url.split("://")
      raise "update only works for gsheet, not #{handler}" unless handler=='gsheet'
      sheet = Mobilize::Gsheet.find_or_create_by_path(sheet_path,u.email)
      sheet.add_or_update_rows(fixture_raw)
    else
      raise "unknown options #{options.to_s}"
    end
    return true
  end

  #checks output sheet for matching string or minimum length
  def TestHelper.check_output(target_url, options={})
    u = TestHelper.owner_user
    handler, sheet_path = target_url.split("://")
    handler = nil
    sheet = Mobilize::Gsheet.find_by_path(sheet_path,u.email)
    raise "no output found" if sheet.nil?
    output = sheet.to_tsv
    if options['match']
      return true if output == options['match']
    elsif options['min_length']
      return true if output.length >= options['min_length']
    else
      raise "unknown check options #{options.to_s}"
    end
    return true
  end

end
