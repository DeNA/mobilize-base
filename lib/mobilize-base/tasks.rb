# require 'resque/tasks'
# will give you the resque tasks

namespace :mobilize do

  desc "Start a Resque worker"
  task :work do
    require 'resque'
    require 'mobilize-base'

    begin
      worker = Resque::Worker.new(Mobilize::Resque.config['queue_name'])
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end

  desc "Set up config and log folders and files"
  task :setup do
    sample_dir = File.dirname(__FILE__) + '/../samples/'
    sample_files = Dir.entries(sample_dir)
    config_dir = "#{ENV['PWD']}/config/"
    log_dir = "#{ENV['PWD']}/log/"
    unless File.exists?(config_dir)
      puts "creating config dir"
      `mkdir #{config_dir}`
    end
    unless File.exists?(log_dir)
      puts "creating log dir"
      `mkdir #{log_dir}`
    end
    sample_files.each do |fname|
      unless File.exists?("#{config_dir}#{fname}")
        puts "creating config/#{fname}"
        `cp #{sample_dir}#{fname} #{config_dir}#{fname}`
      end
    end
  end
end
