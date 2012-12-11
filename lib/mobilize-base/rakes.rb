# require 'resque/tasks'
# will give you the resque tasks

namespace :mobilize_base do
  raise "Please provide MOBILIZE_ENV" unless ENV['MOBILIZE_ENV']
  require 'mobilize-base'
  desc "Start a Resque worker"
  task :work do
    begin
      #require specified mobilize gems
      Mobilize::Base.config('jobtracker')['extensions'].each do |e|
        require e
      end
    rescue Exception=>exc
    end

    begin
      worker = Resque::Worker.new(Mobilize::Resque.config['queue_name'])
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
  desc "Kill idle workers not in sync with repo"
  task :kill_idle_and_stale_workers do
    Mobilize::Jobtracker.kill_idle_and_stale_workers
  end
  desc "Make sure workers are prepped"
  task :prep_workers do
    Mobilize::Jobtracker.prep_workers
  end
  desc "kill all old resque web, start new one with env params"
  task :resque_web do
    port = Mobilize::Base.config('resque')['web_port']
    config_dir = (ENV['MOBILIZE_CONFIG_DIR'] ||= "config/mobilize/")
    full_config_dir = "#{ENV['PWD']}/#{config_dir}"
    resque_web_extension_path = "#{full_config_dir}resque_web.rb"
    #kill any resque-web for now
    `ps aux | grep resque-web | awk '{print $2}' | xargs kill`
    command = "bundle exec resque-web -p #{port.to_s} #{resque_web_extension_path}"
    `#{command}`
  end
  desc "create indexes for all base models in mongodb"
  task :create_indexes do
    ["Dataset","Job","Runner","Task","User"].each do |m|
      "Mobilize::#{m}".constantize.create_indexes
    end
  end
end
namespace :mobilize do
  desc "Set up config and log folders and files"
  task :setup do
    config_dir = (ENV['MOBILIZE_CONFIG_DIR'] ||= "config/mobilize/")
    log_dir = (ENV['MOBILIZE_LOG_DIR'] ||= "log/")
    sample_dir = File.dirname(__FILE__) + '/../samples/'
    sample_files = Dir.entries(sample_dir)
    full_config_dir = "#{ENV['PWD']}/#{config_dir}"
    full_log_dir = "#{ENV['PWD']}/#{log_dir}"
    unless File.exists?(full_config_dir)
      puts "creating #{config_dir}"
      `mkdir #{full_config_dir}`
    end
    unless File.exists?(full_log_dir)
      puts "creating #{log_dir}"
      `mkdir #{full_log_dir}`
    end
    sample_files.each do |fname|
      unless File.exists?("#{full_config_dir}#{fname}")
        puts "creating #{config_dir}#{fname}"
        `cp #{sample_dir}#{fname} #{full_config_dir}#{fname}`
      end
    end
  end
end
