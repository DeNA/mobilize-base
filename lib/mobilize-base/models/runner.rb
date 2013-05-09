module Mobilize
  class Runner
    include Mobilize::RunnerHelper
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :active, type: Boolean
    field :status, type: String
    field :started_at, type: Time
    field :status_at, type: Time
    field :completed_at, type: Time

    index({ path: 1})

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

    def Runner.find_or_create_by_path(path)
      Runner.where(:path=>path).first || Runner.create(:path=>path,:active=>true)
    end

    def read_gsheet(gdrive_slot)
      r = self
      #argument converts line breaks in cells to spaces
      gsheet_tsv = r.gsheet(gdrive_slot).to_tsv(" ")
      #turn it into a hash array
      gsheet_hashes = gsheet_tsv.tsv_to_hash_array
      #go through each job, update relevant job with its params
      done_jobs = []
      #parse out the jobs and update the Job collection
      gsheet_hashes.each do |gsheet_hash|
        #skip non-jobs or jobs without required values
        next if (gsheet_hash['name'].to_s.first == "#" or ['name','active','trigger','stage1'].select{|c| gsheet_hash[c].to_s.strip==""}.length>0)
        j = Job.update_by_user_name_and_hash(r.user.name,gsheet_hash)
        r.update_status("Updated #{j.path} stages at #{Time.now.utc}")
        #add this job to list of read ones
        done_jobs << j
      end
      #delete user jobs that are not included in Runner
      (r.jobs.map{|j| j.path} - done_jobs.map{|j| j.path}).each do |gsheet_hash_path|
        j = Job.where(:path=>gsheet_hash_path).first
        j.delete if j
        r.update_status("Deleted job:#{gsheet_hash_path}")
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
      upd_rows = upd_rows = upd_jobs.map do |j|
        uj = {'name'=>j.name, 'status'=>j.status}
        #jobs can only be turned off
        #automatically, not back on
        if uj.active==false
          uj['active'] = false
        end
        uj
      end
      jobs_gsheet.add_or_update_rows(upd_rows)
      r.update_status("gsheet updated")
      return true
    end

    def worker
      r = self
      Mobilize::Resque.find_worker_by_path(r.path)
    end

    def enqueue!
      r = self
      ::Resque::Job.create("mobilize",Runner,r.path,{})
      return true
    end
  end
end
