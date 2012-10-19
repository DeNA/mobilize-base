class Requestor
  include Mongoid::Document
  include Mongoid::Timestamps
  field  :email, type: String
  field  :oauth, type: String
  field  :name, type: String
  field  :first_name, type: String
  field  :last_name, type: String
  field  :admin_role, type: String

  validates_presence_of :name, :message => ' cannot be blank.'
  validates_uniqueness_of :name, :message => ' has already been used.'

  after_create :add_defaults

  before_destroy :destroy_jobs

  def Requestor.find_or_create_by_name(name)
    r=Requestor.where(:name=>name).first
    r=Requestor.create(:name=>name) unless r
    return r
  end

  def Requestor.find_by_name(name)
    return Requestor.where(:name=>name).first
  end

  def add_defaults
    r = self
    #assume email is name + ngmoco.com
    r.email ||= r.name + "@ngmoco.com"
    r.save!
    return true
  end

  def jobs(jname=nil)
    r = self
    js = Job.find_all_by_requestor_id(r.id.to_s)
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
    Dataset.find_all_by_handler_and_requestor_id('gsheet',r.id.to_s)
  end

  def run_jobs
    r = self
    r.sync_jobs
    r.jobs.each do |j|
      begin
        j.enqueue! if j.active and j.is_due?
      rescue ScriptError,StandardError => exc
        #update errors
        j.update_attributes(:last_error=>exc.to_s,:last_trace=>exc.backtrace.to_s)
      end
    end
    #sync jobs again so user can receive updates queueing etc.
    r.sync_jobs
  end

  def sync_jobs
    #this method syncs a user's Jobs with the database,
    #then creates jobs
    #find or create jobs book and sheet
    r = self
    jobspec = r.find_or_create_gbook_by_title(r.jobspec_title)
    jobs_name = [r.jobspec_title,"Jobs"].join("/")
    jobs_sheet = r.find_or_create_gsheet_by_name(jobs_name)
    #skip if the job sheet is a sample
    if jobs_sheet.input_value(1,1).downcase.starts_with?("=importrange")
      (r.name + " sample jobsheet skipped").oputs
      return true
    end
    #record formulas in grid for later rewrite
    calc_cells = []
    (2..jobs_sheet.num_rows.to_i).each do |r_i|
      (1..jobs_sheet.num_cols.to_i).each do |c_i|
        cell_input = jobs_sheet.input_value(r_i,c_i)
        if cell_input.starts_with?("=")
          calc_cells << {'row_i'=>r_i,"col_i"=>c_i,"value"=>cell_input}
          #%{(#{r_i.to_s},#{c_i.to_s}) => #{cell_input}}.oputs
        end
      end
    end
    rem_jobs = jobs_sheet.to_tsv.tsv_to_hash_array
    #go through each job, update relevant job with its params
    loc_jobs = []
    rem_jobs.each_with_index do |rj,rj_i|
      #skip bad rows
      next if (rj['name'].to_s.first=="#" or ['name','schedule','from_handler','to_handler','active'].select{|c| rj[c].to_s.strip==""}.length>0)
      j=Job.find_or_create_by_requestor_id_and_name(rj['name'],r.id.to_s)
      #update top line params
      j.update_attributes(:active=>rj['active'],
                          :schedule=>rj['schedule'],
                          :from_handler=>rj['from_handler'],
                          :to_handler=>rj['to_handler'],
                          :param_source=>rj['param_source'],
                          :params=>rj['params'],
                          :destination=>rj['destination'])
      #update laststatus with "Created job for" if job is due
      j.update_status("Due and active at #{Time.now.utc}") if j.is_due? and j.active
      #update the hash array's laststatus and datalink params
      #from the local
      rj['last_status']=j.status.to_s.gsub("\n",";").gsub("\t"," ")
      rj['last_error']=j.last_error.to_s.gsub("\n",";").gsub("\t"," ")
      rj['destination_url']=j.destination_url.to_s
      #rewrite any formulas that are in this row
      row_calc_cells = calc_cells.select{|c| c['row_i']==(rj_i+2)}
      row_calc_cells.each do |rcc|
        key = rj.keys[rcc['col_i']-1]
        rj[key] = rcc['value']
        #"Rewrote row #{rcc['row_i']} col #{rcc['col_i']} to #{rcc['value']}".oputs
      end
      #add this job to list of local ones
      loc_jobs << j
    end
    job_upload_tsv = rem_jobs.hash_array_to_tsv
    #make sure headers are set correctly
    job_upload_rows = job_upload_tsv.split("\n")
    job_upload_rows[0] = %w{name active schedule last_status last_error destination_url from_handler to_handler param_source params destination}.join("\t")
    #don't allow line breaks within row
    job_upload_tsv = job_upload_rows.map{|r| r.gsub("\n",";")}.join("\n")
    #upload tsv back up directly, no temp file
    #don't check here - the remote changes all the time
    jobs_sheet.write(job_upload_tsv,check=false)
    #deactivate requestor jobs that are not included in sheet;
    #this makes sure we don't run obsolete jobs
    (r.jobs.map{|j| j.id.to_s} - loc_jobs.map{|j| j.id.to_s}).each do |rjid|
      j = rjid.j
      if j.active
        j.update_attributes(:active=>false)
        "Deactivated job:#{r.name}=>#{j.name}".oputs
      end
    end
    (r.name + " jobs updated").oputs
    return true
  end

  def jobspec_title
    r = self
    prefix = "Jobspec_"
    suffix = ""
    if Rails.env == 'staging'
      suffix = "_stg"
    elsif Rails.env == 'development' or Rails.env == 'pry_dev'
      suffix = "_dev"
    elsif Rails.env == 'production' or Rails.env == 'integration'
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
    book_dst.update_attributes(:requestor_id=>r.id.to_s) if book_dst.requestor_id.nil?
    book = Gbooker.find_or_create_by_dst_id(book_dst.id.to_s)
    #check if this is a jobspec, and if so, whether it has necessary master tabs
    r.prep_jobspec if (title == r.jobspec_title and r.name != 'mobilize')
    return book
  end

  def prep_jobspec
    r = self
    book_dst = Dataset.find_by_handler_and_name('gbooker',r.jobspec_title)
    book = Gbooker.find_or_create_by_dst_id(book_dst.id.to_s)
    #get mobilize user jobspec master sheets
    mr = Requestor.find_or_create_by_name('mobilize')
    mbook_dst = Dataset.find_or_create_by_requestor_id_and_handler_and_name(mr.id.to_s,'gbooker',mr.jobspec_title)
    mbook = Gbooker.find_or_create_by_dst_id(mbook_dst.id.to_s)
    msheets = mbook.worksheets.select{|s| s.title.ends_with?('Master')}
    #compare with current jobspec sheets
    sheet_titles = book.worksheets.map{|s| s.title}
    msheets.each do |ms|
      stitle = ms.title.gsub('Master','')
      if !(sheet_titles.include?(stitle))
        newsheet = book.add_worksheet(stitle)
        #docs by default take cols A:J
        formula = %{=ImportRange("#{mbook.resource_id.split(":").last}","#{ms.title}!A:J")}
        newsheet[1,1] = formula
        newsheet.save
      end
    end
    #delete Sheet1 if there are other sheets
    if book.worksheets.length>1
      sheet1 = book.worksheets.select{|s| s.title == "Sheet 1"}.first
      sheet1.delete if sheet1
    end
  end

  def find_or_create_gsheet_by_name(name)
    r = self
    sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheet',name)
    sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if sheet_dst.requestor_id.nil?
    sheet = Gsheeter.find_or_create_by_dst_id(sheet_dst.id.to_s)
    return sheet
  end
end
