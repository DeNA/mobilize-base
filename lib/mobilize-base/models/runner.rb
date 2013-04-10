module Mobilize
  class Runner
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :active, type: Boolean
    field :status, type: String
    field :started_at, type: Time
    field :status_at, type: Time
    field :completed_at, type: Time

    index({ path: 1})

    def headers
      %w{name active trigger status stage1 stage2 stage3 stage4 stage5}
    end

    def title
      r = self
      r.path.split("/").first
    end

    def worker
      r = self
      Mobilize::Resque.find_worker_by_path(r.path)
    end

    def Runner.find_by_path(path)
      Runner.where(:path=>path).first
    end

    def Runner.find_by_title(title)
      Runner.where(:path=>"#{title}/jobs").first
    end
    def Runner.perform(id,*args)
      r = Runner.find_by_path(id)
      #get gdrive slot for read
      gdrive_slot = Gdrive.slot_worker_by_path(r.path)
      unless gdrive_slot
        r.update_status("no gdrive slot available")
        return false
      end
      r.update_attributes(:started_at=>Time.now.utc)
      begin
        #make sure any updates to activity are processed first
        #as in when someone runs a "once" job that has completed
        r.update_gsheet(gdrive_slot) 
        #read the jobs in the gsheet and update models with news
        r.read_gsheet(gdrive_slot)
        #queue up the jobs that are due and active
      rescue => exc
        #log the exception, but continue w job processing
        #This ensures jobs are still processed if google drive goes down
        r.update_status("Failed to read or update gsheet with #{exc.to_s} #{exc.backtrace.join(";")}")
      end
      r.jobs.each do |j|
        begin
          if j.is_due?
            j.update_attributes(:active=>false) if j.trigger=='once'
            s = j.stages.first
            s.update_attributes(:retries_done=>0)
            s.enqueue!
          end
        rescue ScriptError, StandardError => exc
          r.update_status("Failed to enqueue #{j.path} with #{exc.to_s}")
          j.update_attributes(:active=>false)
        end
      end
      r.update_gsheet(gdrive_slot)
      r.update_attributes(:completed_at=>Time.now.utc)
    end

    def dataset
      r = self
      Dataset.find_or_create_by_handler_and_path("gsheet",r.path)
    end

    def Runner.find_or_create_by_path(path)
      Runner.where(:path=>path).first || Runner.create(:path=>path,:active=>true)
    end

    def gbook(gdrive_slot)
      r = self
      title = r.path.split("/").first
      Gbook.find_by_path(title,gdrive_slot)
    end

    def gsheet(gdrive_slot)
      r = self
      u = r.user
      jobs_sheet = Gsheet.find_by_path(r.path,gdrive_slot)
      #make sure the user has a runner with a jobs sheet and has write privileges on the spreadsheet
      unless (jobs_sheet and jobs_sheet.spreadsheet.acl_entry(u.email).ie{|e| e and e.role=="writer"})
        #only give the user edit permissions if they're the ones
        #creating it
        jobs_sheet = Gsheet.find_or_create_by_path(r.path,gdrive_slot)
        unless jobs_sheet.spreadsheet.acl_entry(u.email).ie{|e| e and e.role=="owner"}
          jobs_sheet.spreadsheet.update_acl(u.email,"writer")
        end
        jobs_sheet.add_headers(r.headers)
        begin;jobs_sheet.delete_sheet1;rescue;end #don't care if sheet1 deletion fails
      end
      return jobs_sheet
    end

    def read_gsheet(gdrive_slot)
      r = self
      #argument converts line breaks in cells to spaces
      gsheet_tsv = r.gsheet(gdrive_slot).to_tsv(" ")
      #turn it into a hash array
      gsheet_jobs = gsheet_tsv.tsv_to_hash_array
      #go through each job, update relevant job with its params
      done_jobs = []
      #parse out the jobs and update the Job collection
      gsheet_jobs.each_with_index do |rj,rj_i|
        #skip non-jobs or jobs without required values
        next if (rj['name'].to_s.first == "#" or ['name','active','trigger','stage1'].select{|c| rj[c].to_s.strip==""}.length>0)
        j = Job.find_or_create_by_path("#{r.path}/#{rj['name']}")
        #update top line params
        j.update_attributes(:active => rj['active'],
                            :trigger => rj['trigger'])
        (1..5).to_a.each do |s_idx|
          stage_string = rj["stage#{s_idx.to_s}"]
          s = Stage.find_by_path("#{j.path}/stage#{s_idx.to_s}")
          if stage_string.to_s.length==0
            #delete this stage and all stages after
            if s
              j = s.job
              j.stages[(s.idx-1)..-1].each{|ps| ps.delete}
              #just in case
              s.delete
            end
            break
          elsif s.nil?
            #create this stage
            s = Stage.find_or_create_by_path("#{j.path}/stage#{s_idx.to_s}")
          end
          #parse command string, update stage with it
          s_handler, call, param_string = [""*3]
          stage_string.split(" ").ie do |spls|
            s_handler = spls.first.split(".").first
            call = spls.first.split(".").last
            param_string = spls[1..-1].join(" ").strip
          end
          s.update_attributes(:call=>call, :handler=>s_handler, :param_string=>param_string)
        end
        r.update_status("Updated #{j.path} stages at #{Time.now.utc}")
        #add this job to list of read ones
        done_jobs << j
      end
      #delete user jobs that are not included in Runner
      (r.jobs.map{|j| j.path} - done_jobs.map{|j| j.path}).each do |rj_path|
        j = Job.where(:path=>rj_path).first
        j.delete if j
        r.update_status("Deleted job:#{rj_path}")
      end
      r.update_status("jobs read at #{Time.now.utc}")
      return true
    end

    def update_gsheet(gdrive_slot)
      r = self
      #there's nothing to update if runner has never had a completed at
      return false unless r.completed_at
      jobs_gsheet = r.gsheet(gdrive_slot)
      upd_jobs = r.jobs.select{|j| j.status_at and j.status_at.to_f > j.runner.completed_at.to_f}
      upd_rows = upd_jobs.map{|j| {'name'=>j.name, 'active'=>j.active, 'status'=>j.status}}
      jobs_gsheet.add_or_update_rows(upd_rows)
      r.update_status("gsheet updated")
      return true
    end

    def jobs(jname=nil)
      r = self
      js = Job.where(:path=>/^#{r.path.escape_regex}/).to_a
      if jname
        return js.sel{|j| j.name == jname}.first
      else
        return js
      end
    end

    def user
      r = self
      user_name = r.path.split("_")[1..-1].join("_").split("(").first.split("/").first
      User.where(:name=>user_name).first
    end

    def update_status(msg)
      r = self
      r.update_attributes(:status=>msg, :status_at=>Time.now.utc)
      Mobilize::Resque.set_worker_args_by_path(r.path,{'status'=>msg})
      return true
    end

    def is_working?
      r = self
      Mobilize::Resque.active_paths.include?(r.path)
    end

    def is_due?
      r = self.reload
      return false if r.is_working?
      prev_due_time = Time.now.utc - Jobtracker.runner_read_freq
      return true if r.started_at.nil? or r.started_at < prev_due_time
    end

    def enqueue!
      r = self
      ::Resque::Job.create("mobilize",Runner,r.path,{})
      return true
    end
  end
end
