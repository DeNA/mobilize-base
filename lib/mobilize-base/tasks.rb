# require 'resque/tasks'
# will give you the resque tasks

namespace :mobilize do
  task :setup

  desc "Start a Resque worker"
  task :work => :setup do
    require 'resque'

    queues = ['MOBILIZE_JOBTRACKER','MOBILIZE_WORKER'] 

    begin
      worker = Resque::Worker.new(*queues)
#      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
#      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    if ENV['BACKGROUND']
      unless Process.respond_to?('daemon')
          abort "env var BACKGROUND is set, which requires ruby >= 1.9"
      end
      Process.daemon(true)
    end

#    Resque.logger.info "Starting worker #{worker}"
    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end

  desc "Use Bluepill to start/restart workers"
  task :start=>:setup do
    require 'mobilize-base'
    require 'bluepill'
    app_name = "mobilize-resque"
    app_env = Mobilize::Base.env
    app_root = Mobilize::Base.root
    num_workers = ENV['NUM_WORKERS'] || 4
    pid_dir = ENV['PID_DIR'] || "/tmp/#{app_name}/pid/"
    log_dir = ENV['LOG_DIR'] || "/tmp/#{app_name}/log/"
    bp_base_dir = "/tmp/#{app_name}/base/"
    bp_base_socks_dir = ENV['BP_BASE_DIR'] || "/tmp/#{app_name}/base/socks/"
    bp_base_pids_dir = ENV['BP_BASE_DIR'] || "/tmp/#{app_name}/base/pids/"

    bp_log_file = ENV['BP_LOG_FILE'] || "#{log_dir}bluepill.log"

    [bp_base_socks_dir, bp_base_pids_dir, pid_dir, log_dir].each{|d| FileUtils.mkpath(d) }

    Bluepill.application(app_name, :log_file => bp_log_file, :base_dir=>bp_base_dir) do |app|
      num_workers.times do |i|
        app.process("#{app_name}-#{i}") do |process|
          #this gets passed to resque so it knows to create/write to pidfile bluepill is looking for
          pid_name = "#{pid_dir}#{app_name}-#{i}"
          ENV['PIDFILE']="#{pid_name}.pid"
          process.start_command = "/usr/bin/rake -f #{app_root}/Rakefile mobilize:work"
          process.pid_file = ENV['PIDFILE']
          process.stop_command = "kill -QUIT {{PID}}"
          process.daemonize = true
          process.checks :cpu_usage, :every => 30.seconds, :below => 5, :times => 10
          process.checks :mem_usage, :every => 30.seconds, :below => 550.megabytes, :times => 10
          process.stdout = "#{log_dir}#{pid_name}.out"
          process.stderr = "#{log_dir}#{pid_name}.err"
            process.monitor_children do |child_process|
              child_process.checks :cpu_usage, :every => 30.seconds, :below => 5, :times => 10
              child_process.checks :mem_usage, :every => 30.seconds, :below => 550.megabytes, :times => 10
              child_process.stop_command = "kill -QUIT {{PID}}"
            end
        end
      end
    end
  end
end
