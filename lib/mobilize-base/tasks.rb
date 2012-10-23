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

end
