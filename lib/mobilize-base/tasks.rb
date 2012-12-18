namespace :mobilize_base do
  desc "Start a Resque worker"
  task :work do
    require 'mobilize-base'
    begin
      #require specified mobilize gems
      Mobilize::Base.config('jobtracker')['extensions'].each do |e|
        require e
      end
    rescue Exception=>exc
      #do nothing
    end

    begin
      worker = Resque::Worker.new(Mobilize::Resque.config['queue_name'])
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
  desc "Kill all Resque workers"
  task :kill_workers do
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_workers
  end
  desc "Kill idle workers not in sync with repo"
  task :kill_idle_and_stale_workers do
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_idle_and_stale_workers
  end
    desc "Kill idle workers"
    task :kill_idle_workers do
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_idle_workers
  end
  desc "Make sure there are the correct # of workers, kill if too many"
  task :prep_workers do
    require 'mobilize-base'
    Mobilize::Jobtracker.prep_workers
  end
  desc "Stop Jobtracker"
  task :stop do
    require 'mobilize-base'
    Mobilize::Jobtracker.stop!
  end
  desc "Start Jobtracker"
  task :start do
    require 'mobilize-base'
    Mobilize::Jobtracker.start
  end
  desc "Restart Jobtracker"
  task :restart do
    require 'mobilize-base'
    Mobilize::Jobtracker.restart!
  end
  desc "kill all old resque web processes, start new one with resque_web.rb extension file"
  task :resque_web do
    require 'mobilize-base'
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
    require 'mobilize-base'
    ["Dataset","Job","Runner","Task","User"].each do |m|
      "Mobilize::#{m}".constantize.create_indexes
    end
  end
  desc "Set up config and log folders and files, populate from samples"
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
