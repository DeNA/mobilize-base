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

  def Requestor.jobs_sheet_headers
    %w{name active schedule status last_error destination_url read_handler write_handler param_source params destination}
  end

  def Requestor.perform(id,*args)
    r = id.r
    jobs_sheet = r.jobs_sheet
    #write headers to sheet
    Requestor.jobs_sheet_headers.each_with_index do |h,h_i|
      jobs_sheet[1,h_i+1] = h
    end
    jobs_sheet.save
    #pull down the jobs sheet 
    #record jobs in DB
    #deactivate jobs not in sheet
    r.pull_jobs
    #queue up the jobs that are due and active
    r.jobs.each do |j|
      begin
        j.enqueue! if j.active and j.is_due?
      rescue ScriptError,StandardError => exc
        #update errors
        j.update_attributes(:last_error=>exc.to_s,:last_trace=>exc.backtrace.to_s)
      end
    end
    #push up any updates to status, error, datasource_url etc.
    r.push_jobs
    r.update_attributes(:last_run=>Time.now.utc)
  end

  def jobs_sheet
    r = self
    r.find_or_create_gbook_by_title(r.jobspec_title)
    jobs_name = [r.jobspec_title,"Jobs"].join("/")
    r.find_or_create_gsheet_by_name(jobs_name)
  end

  def pull_jobs
    r = self
    jobs_sheet = r.jobs_sheet
    rem_jobs = jobs_sheet.to_tsv.tsv_to_hash_array
    #go through each job, update relevant job with its params
    loc_jobs = []
    rem_jobs.each_with_index do |rj,rj_i|
      #skip bad rows
      next if (rj['name'].to_s.first == "#" or ['name','schedule','read_handler','write_handler','active'].select{|c| rj[c].to_s.strip==""}.length>0)
      j = Job.find_or_create_by_requestor_id_and_name(r.id,rj['name'])
      #update top line params
      j.update_attributes(:active => rj['active'],
                          :schedule => rj['schedule'],
                          :read_handler => rj['read_handler'],
                          :write_handler => rj['write_handler'],
                          :param_source => rj['param_source'],
                          :params => rj['params'],
                          :destination => rj['destination'])
      #update laststatus with "Created job for" if job is due
      j.update_status("Due and active at #{Time.now.utc}") if j.is_due? and j.active
      #add this job to list of local ones
      loc_jobs << j
    end
    #deactivate requestor jobs that are not included in sheet;
    #this makes sure we don't run obsolete jobs
    (r.jobs.map{|j| j.id} - loc_jobs.map{|j| j.id}).each do |rjid|
      j = rjid.j
      if j.active
        j.update_attributes(:active=>false)
        r.update_status("Deactivated job:#{r.name}=>#{j.name}")
      end
    end
    r.update_status(r.name + " jobs pulled at #{Time.now.utc}")
    return true
  end

  def write_jobs
    r = self
    jobs_sheet = r.jobs_sheet
    rem_jobs = jobs_sheet.to_tsv.tsv_to_hash_array
    #go through each job, update relevant job with its params
    j_writes = []
    headers = Requestor.jobs_sheet_headers
    rem_jobs.each_with_index do |rj,rj_i|
      j = r.jobs(rj['name'])
      jobs_sheet[rj_i+1,headers.index('active')+1] = j.active.to_s
      jobs_sheet[rj_i+1,headers.index('status')+1] = j.status.to_s.gsub("\n",";").gsub("\t"," ")
      jobs_sheet[rj_i+1,headers.index('last_error')+1] = j.last_error.to_s.gsub("\n",";").gsub("\t"," ")
      jobs_sheet[rj_i+1,headers.index('destination_url')+1] = j.destination_url.to_s
    end
    jobs_sheet.save
    r.update_status(r.name + " jobs pushed")
    return true
  end

  def jobspec_title
    r = self
    prefix = "Jobspec_"
    suffix = ""
    if Mobilize::Base.env == 'staging'
      suffix = "_stg"
    elsif Mobilize::Base.env == 'development' or Mobilize::Base.env == 'pry_dev'
      suffix = "_dev"
    elsif Mobilize::Base.env == 'production' or Mobilize::Base.env == 'integration'
      suffix = ""
    else
      raise "Invalid environment"
    end
    title = prefix + r.name + suffix
    return title
  end

  #Google doc helper methods

  def find_or_create_gbook_by_title(title)
    r = self
    book_dst = Dataset.find_or_create_by_handler_and_name('gbooker',title)
    #give dst this requestor if none
    book_dst.update_attributes(:requestor_id=>r.id) if book_dst.requestor_id.nil?
    book = Gbooker.find_or_create_by_dst_id(book_dst.id)
    #check if this is a jobspec, and if so, whether it has necessary master tabs
    r.prep_jobspec if (title == r.jobspec_title and r.name != 'mobilize')
    return book
  end

  def find_or_create_gsheet_by_name(name)
    r = self
    sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheet',name)
    sheet_dst.update_attributes(:requestor_id=>r.id) if sheet_dst.requestor_id.nil?
    sheet = Gsheeter.find_or_create_by_dst_id(sheet_dst.id)
    return sheet
  end

  def jobs(jname=nil)
    r = self
    js = Job.find_all_by_requestor_id(r.id)
    if jname
      return js.sel{|s| j.name == jname}.first
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
    Dataset.find_all_by_handler_and_requestor_id('gsheet',r.id)
  end

  def worker
    r = self
    Resque::Mobilize.worker_by_id(r.id)
  end

  def update_status(msg)
    r = self
    r.update_attributes(:status=>msg)
    Resque::Mobilize.update_worker_status(r.worker,msg)
    return true
  end

end
