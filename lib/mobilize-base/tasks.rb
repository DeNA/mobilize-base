# require 'resque/tasks'
# will give you the resque tasks

namespace :mobilize do
  task :setup

  desc "Start a Resque worker"
  task :work => :setup do
    require 'resque'
    require 'mobilize-base'

    begin
      worker = Resque::Worker.new(Mobilize::Resque.config['queue_name'])
#      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
#      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

#   Resque.logger.info "Starting worker #{worker}"
    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
end
