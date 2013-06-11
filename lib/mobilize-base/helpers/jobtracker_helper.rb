module Mobilize
  module Jobtracker
    def Jobtracker.config
      Base.config('jobtracker')
    end

    #modify this to increase the frequency of request cycles
    def Jobtracker.cycle_freq
      Jobtracker.config['cycle_freq']
    end

    def Jobtracker.user_home_dir
      Jobtracker.config['user_home_dir']
    end

    #frequency of notifications
    def Jobtracker.notification_freq
      Jobtracker.config['notification_freq']
    end

    def Jobtracker.runner_read_freq
      Jobtracker.config['runner_read_freq']
    end

    #long running tolerance
    def Jobtracker.max_run_time
      Jobtracker.config['max_run_time']
    end

    def Jobtracker.admins
      Jobtracker.config['admins']
    end

    def Jobtracker.worker
      Resque.find_worker_by_path("jobtracker")
    end

    def Jobtracker.workers(state="all")
      Resque.workers(state)
    end

    def Jobtracker.disabled_methods
      Jobtracker.config['disabled_methods']
    end

    def Jobtracker.status
      args = Jobtracker.get_args
      return args['status'] if args
      job = Resque.jobs.select{|j| j['args'].first=='jobtracker'}.first
      return 'queued' if job
      return 'stopped'
    end

    def Jobtracker.update_status(msg)
      #this is to keep jobtracker from resisting stop commands
      return false if Jobtracker.status=="stopping"
      #Jobtracker has no persistent database state
      Resque.set_worker_args_by_path("jobtracker",{'status'=>msg})
      return true
    end

    def Jobtracker.restart
      Jobtracker.stop!
      Jobtracker.start
    end

    def Jobtracker.set_args(args)
      Resque.set_worker_args(Jobtracker.worker,args)
      return true
    end

    def Jobtracker.get_args
      Resque.get_worker_args(Jobtracker.worker)
    end

    def Jobtracker.kill_workers
      Resque.kill_workers
    end

    def Jobtracker.kill_idle_workers
      Resque.kill_idle_workers
    end

    def Jobtracker.prep_workers
      Resque.prep_workers
    end

    def Jobtracker.failures
      Resque.failures
    end

    def Jobtracker.start
      if Jobtracker.status!='stopped'
        Jobtracker.update_status("Jobtracker still #{Jobtracker.status}")
      else
        #make sure that workers are running and at the right number
        #Resque.prep_workers
        #queue up the jobtracker (starts the perform method)
        Jobtracker.enqueue!
      end
      return true
    end

    def Jobtracker.enqueue!
      ::Resque::Job.create(Resque.queue_name, Jobtracker, 'jobtracker',{})
    end

    def Jobtracker.restart!
      Jobtracker.stop!
      Jobtracker.start
      return true
    end

    def Jobtracker.restart_workers!
      Jobtracker.kill_workers
      sleep 10
      Jobtracker.prep_workers
      Jobtracker.update_status("put workers back on the queue")
    end

    def Jobtracker.stop!
      #send signal for Jobtracker to check for
      Jobtracker.update_status('stopping')
      sleep 5
      i=0
      while Jobtracker.status=='stopping'
        puts "#{Jobtracker.to_s} still on queue, waiting"
        sleep 5
        i+=1
      end
      return true
    end

    def Jobtracker.last_notification
      return Jobtracker.get_args["last_notification"] if Jobtracker.get_args
    end

    def Jobtracker.last_notification=(time)
      Jobtracker.set_args({"last_notification"=>time})
    end

    def Jobtracker.notif_due?
      last_duetime = Time.now.utc - Jobtracker.notification_freq
      return (Jobtracker.last_notification.to_s.length==0 || Jobtracker.last_notification.to_datetime < last_duetime)
    end
  end
end
