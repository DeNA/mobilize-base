module Mobilize
  class Requestor
    include Mongoid::Document
    include Mongoid::Timestamps
    field :email, type: String
    field :oauth, type: String
    field :name, type: String
    field :first_name, type: String
    field :last_name, type: String
    field :admin_role, type: String
    field :last_run, type: Time
    field :status, type: String

    validates_presence_of :name, :message => ' cannot be blank.'
    validates_uniqueness_of :name, :message => ' has already been used.'

    before_destroy :destroy_jobs

    def Requestor.find_or_create_by_name(name)
      r = Requestor.where(:name => name).first
      r = Requestor.create(:name => name) unless r
      return r
    end

    def Requestor.find_or_create_by_email(email)
      r = Requestor.where(:email => email).first
      r = Requestor.create(:email => email) unless r
      user_name = email.split("@").first
      r.update_attributes(:name => user_name) unless r.name.to_s.length>0
      return r
    end

    def Requestor.jobs_sheet_headers
      %w{name active schedule status last_error destination_url read_handler write_handler param_sheets params destination}
    end

    def Requestor.perform(id,*args)
      r = Requestor.find(id.to_s)
      #reserve email account for read
      gdrive_email = Gdriver.get_worker_email_by_mongo_id(id)
      return false unless gdrive_email
      jobs_sheet = r.jobs_sheet(gdrive_email)
      #write headers to sheet
      Requestor.jobs_sheet_headers.each_with_index do |h,h_i|
        jobs_sheet[1,h_i+1] = h
      end
      jobs_sheet.save
      #read the jobs sheet 
      #record jobs in DB
      #deactivate jobs not in sheet
      r.read_jobs(gdrive_email)
      #queue up the jobs that are due and active
      r.jobs.each do |j|
        begin
          j.enqueue! if j.active and j.is_due?
        rescue ScriptError,StandardError => exc
          #update errors
          j.update_attributes(:last_error=>exc.to_s,:last_trace=>exc.backtrace.to_s)
        end
      end
      #write any updates to status, error, datasource_url etc.
      r.write_jobs(gdrive_email)
      r.update_attributes(:last_run=>Time.now.utc)
    end

    def jobs_sheet(gdrive_email)#gdrive_email to read with
      r = self
      r.find_or_create_gbook_by_title(r.jobspec_title,gdrive_email)
      jobs_name = [r.jobspec_title,"Jobs"].join("/")
      r.find_or_create_gsheet_by_name(jobs_name,gdrive_email)
    end

    def read_jobs(gdrive_email)
      r = self
      jobs_sheet = r.jobs_sheet(gdrive_email)
      rem_jobs = jobs_sheet.to_tsv.tsv_to_hash_array
      #go through each job, update relevant job with its params
      loc_jobs = []
      rem_jobs.each_with_index do |rj,rj_i|
        #skip bad rows
        next if (rj['name'].to_s.first == "#" or ['name','schedule','read_handler','write_handler','active'].select{|c| rj[c].to_s.strip==""}.length>0)
        j = Job.find_or_create_by_requestor_id_and_name(r.id.to_s,rj['name'])
        #update top line params
        j.update_attributes(:active => rj['active'],
                            :schedule => rj['schedule'],
                            :read_handler => rj['read_handler'],
                            :write_handler => rj['write_handler'],
                            :param_sheets => rj['param_sheets'],
                            :params => rj['params'],
                            :destination => rj['destination'])
        #update laststatus with "Created job for" if job is due
        j.update_status("Due and active at #{Time.now.utc}") if j.is_due? and j.active
        #add this job to list of local ones
        loc_jobs << j
      end
      #deactivate requestor jobs that are not included in sheet;
      #this makes sure we don't run obsolete jobs
      (r.jobs.map{|j| j.id.to_s} - loc_jobs.map{|j| j.id.to_s}).each do |rjid|
        j = Job.find(rjid)
        if j.active
          j.update_attributes(:active=>false)
          r.update_status("Deactivated job:#{r.name}=>#{j.name}")
        end
      end
      r.update_status(r.name + " jobs read at #{Time.now.utc}")
      return true
    end

    def write_jobs(gdrive_email) #gdrive_email to update with
      r = self
      jobs_sheet = r.jobs_sheet(gdrive_email)
      rem_jobs = jobs_sheet.to_tsv.tsv_to_hash_array
      #go through each job, update relevant job with its params
      headers = Requestor.jobs_sheet_headers
      #write headers
      headers.each_with_index do |h,h_i|
        jobs_sheet[1,h_i+1] = h
      end
      #write rows
      rem_jobs.each_with_index do |rj,rj_i|
        #skip bad rows
        next if (rj['name'].to_s.first == "#" or ['name','schedule','read_handler','write_handler','active'].select{|c| rj[c].to_s.strip==""}.length>0)
        j = r.jobs(rj['name'])
        #update active to false if this was a run once
        j.update_attributes(:active=>false) if j.schedule.to_s == 'once'
        jobs_sheet[rj_i+2,headers.index('active')+1] = j.active.to_s
        jobs_sheet[rj_i+2,headers.index('status')+1] = j.status.to_s.gsub("\n",";").gsub("\t"," ")
        jobs_sheet[rj_i+2,headers.index('last_error')+1] = j.last_error.to_s.gsub("\n",";").gsub("\t"," ")
        jobs_sheet[rj_i+2,headers.index('destination_url')+1] = j.destination_url.to_s
      end
      jobs_sheet.save
      r.update_status(r.name + " jobs written")
      return true
    end

    def jobspec_title
      r = self
      prefix = "Jobspec_"
      suffix = ""
      if Mobilize::Base.env == 'development'
        suffix = "_dev"
      elsif Mobilize::Base.env == 'test' or Mobilize::Base.env == 'pry_dev'
        suffix = "_test"
      elsif Mobilize::Base.env == 'production' or Mobilize::Base.env == 'integration'
        suffix = ""
      else
        raise "Invalid environment"
      end
      title = prefix + r.name + suffix
      return title
    end

    #Google doc helper methods

    def find_or_create_gbook_by_title(title,gdrive_email)
      r = self
      book_dst = Dataset.find_or_create_by_handler_and_name('gbooker',title)
      #give dst this requestor if none
      book_dst.update_attributes(:requestor_id=>r.id.to_s) if book_dst.requestor_id.nil?
      book = Gbooker.find_or_create_by_dst_id(book_dst.id.to_s,gdrive_email)
      return book
    end

    def find_or_create_gsheet_by_name(name,gdrive_email)
      r = self
      sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',name)
      sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if sheet_dst.requestor_id.nil?
      sheet = Gsheeter.find_or_create_by_dst_id(sheet_dst.id.to_s,gdrive_email)
      return sheet
    end

    def jobs(jname=nil)
      r = self
      js = Job.find_all_by_requestor_id(r.id.to_s)
      if jname
        return js.sel{|j| j.name == jname}.first
      else
        return js
      end
    end

    def destroy_jobs
      r = self
      r.jobs.each{|s| s.delete}
    end

    def gsheets
      r = self
      Dataset.find_all_by_handler_and_requestor_id('gsheet',r.id.to_s)
    end

    def worker
      r = self
      Mobilize::Resque.find_worker_by_mongo_id(r.id.to_s)
    end

    def update_status(msg)
      r = self
      r.update_attributes(:status=>msg)
      Mobilize::Resque.update_job_status(r.id.to_s,msg)
      return true
    end

    def is_working?
      r = self
      Mobilize::Resque.active_mongo_ids.include?(r.id.to_s)
    end

    def is_due?
      r = self
      return false if r.is_working?
      last_due_time = Time.now.utc - Jobtracker.requestor_refresh_freq
      return true if r.last_run.nil? or r.last_run < last_due_time
    end

    def enqueue!
      r = self
      ::Resque::Job.create("mobilize",Requestor,r.id.to_s,{"name"=>r.name})
      return true
    end

  end
end
