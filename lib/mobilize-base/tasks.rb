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
    rails_env,ENV['RAILS_ENV'] = ["production"]*2
    rails_root  = ENV['RAILS_ROOT'] || "/var/apps/mobilize/current/"
    num_workers = rails_env == 'production' ? 36 : 4

    Bluepill.application("mobilize", :log_file => "/var/log/bluepill.log") do |app|
      app.working_dir = rails_root
      app.uid = "deploy"
      app.gid = "admin"
      num_workers.times do |i|
        app.process("resque-#{i}") do |process|
          #this gets passed to resque so it knows to create/write to pidfile bluepill is looking for
          ENV['PIDFILE']="#{rails_root}log/pids/resque-#{i}.pid"
          process.group = "resque"
          process.start_command = "/usr/bin/rake -f #{rails_root}Rakefile environment resque:work"
          process.pid_file = ENV['PIDFILE']
          process.stop_command = "kill -QUIT {{PID}}"
          process.daemonize = true
          process.checks :cpu_usage, :every => 30.seconds, :below => 5, :times => 10
          process.checks :mem_usage, :every => 30.seconds, :below => 550.megabytes, :times => 10
          process.stdout = process.stderr = "/tmp/bluepill.log"
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
