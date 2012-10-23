class Gdriver

  def Gdriver.config_file
    YAML.load_file("#{Mobilize::Base.root}/mobilize.yml")
  end

  def Gdriver.owner_account
    Gdriver.config_file['owner_account']
  end

  def Gdriver.password
    Gdriver.config_file['owner_password']
  end

  def Gdriver.admin_accounts
    Gdriver.config_file['admin_accounts']
  end

  def Gdriver.worker_accounts
    Gdriver.config_file['worker_accounts']
  end

  #account management - used to make sure not too many accounts get used at the same time
  def Gdriver.get_worker_account
    active_accts = Jobtracker.worker_args.map{|a| a[1]['account'] if a[1]}.compact
    Gdriver.worker_accounts.sort_by{rand}.each do |ga|
      return ga unless active_accts.include?(ga)
    end
    #return false if none are available
    return false
  end

  def Gdriver.root(account=nil)
    account ||= Gdriver.owner_account
    #http
    GoogleDrive.login(account,Gdriver.password)
  end

  def Gdriver.files(account=nil)
    root = Gdriver.root(account)
    #http
    root.files
  end

  def Gdriver.books(account=nil)
    Gdriver.files(account).select{|f| f.class==GoogleDrive::Spreadsheet}
  end

  def Gdriver.txts(account=nil)
    Gdriver.files(account).select{|f| f.class==GoogleDrive::File and f.title.ends_with?("txt.gz")}
  end

end

class Gfiler
  def Gfiler.find_by_title(title,account=nil)
    Gdriver.files(account).select{|f| f.title==title}.first
  end

  def Gfiler.find_by_dst_id(dst_id,account=nil)
    dst = dst_id.dst
    Gfiler.find_by_title(dst.path,account)
  end

  def Gfiler.add_admin_acl_by_dst_id(dst_id)
    #adds admins and workers as writers
    file = Gfiler.find_by_dst_id(dst_id)
    file.add_admin_acl
    return true
  end

  def Gfiler.add_admin_acl_by_title(title)
    file = Gfiler.find_by_title(title)
    file.add_admin_acl
    return true
  end

  def Gfiler.add_worker_acl_by_title(title)
    file = Gfiler.find_by_title(title)
    file.add_worker_acl
    return true
  end

  def Gfiler.update_acl_by_dst_id(dst_id,account,role="writer",edit_account=nil)
    dst = dst_id.dst
    Gfiler.update_acl_by_title(dst.path,account,role,edit_account)
  end

  def Gfiler.update_acl_by_title(title,account,role="writer",edit_account=nil)
    file = Gfiler.find_by_title(title,edit_account)
    raise "File #{title} not found" unless file
    file.update_acl(account,role)
  end
end

class GoogleDrive::File

  def add_worker_acl
    f = self
    return true if f.has_worker_acl?
    (Gdriver.worker_accounts).each do |a| 
      f.update_acl(a)
    end
  end

  def add_admin_acl
    f = self
    #admin includes workers
    return true if f.has_admin_acl?
    (Gdriver.admin_accounts + Gdriver.worker_accounts).each do |a| 
      f.update_acl(a)
    end
  end

  def has_admin_acl?
    f = self
    curr_accounts = f.acls.map{|a| a.scope}.sort
    admin_accounts = Gdriver.admin_accounts.sort
    if (curr_accounts & admin_accounts) == admin_accounts
      return true
    else
      return false
    end
  end

  def has_worker_acl?
    f = self
    curr_accounts = f.acls.map{|a| a.scope}.sort
    worker_accounts = Gdriver.worker_accounts.sort
    if (curr_accounts & worker_accounts) == worker_accounts
      return true
    else
      return false
    end
  end

  def update_acl(account,role="writer")
    f = self
    #need these flags for HTTP retries
    update_complete = false
    retries = 0
    #create req_acl hash to add to current acl
    if entry = f.acl_entry(account)
      if [nil,"none","delete"].include?(role)
        f.acl.delete(entry)
      elsif entry.role != role and ['reader','writer','owner'].include?(role)
        entry.role=role
        f.acl.update_role(entry,entry.role,notify=false)
      elsif !['reader','writer','owner'].include?(role)
        raise "Invalid role #{role}"
      end
    else
      f.acl.push({:scope_type=>"user",:scope=>account,:role=>role},notify=false)
    end
    return true
  end
  def acls
    f = self
    f.acl.to_enum.to_a
  end
  def acl_entry(account)
    f = self
    curr_acls = f.acls
    curr_accounts = curr_acls.map{|a| a.scope}
    f.acls.select{|a| ['group','user'].include?(a.scope_type) and a.scope == account}.first
  end

  def entry_hash
    f = self
    dfe_xml = f.document_feed_entry.to_xml
    begin
      Hash.from_xml(dfe_xml)[:entry]
    rescue
      {}
    end
  end
end

class Gbooker

  def Gbooker.find_or_create_by_title(title,account)
    books = Gdriver.books(account).select{|b| b.title==title}
    #there should only be one book with each title, otherwise we have fail
    book = nil
    if books.length>1
      #some idiot process created a duplicate book.
      #Fix by renaming all but one with dst entry's key
      dst = Dataset.find_by_handler_and_name('gbooker',title)
      dkey = dst.url.split("key=").last
      books.each do |b|
        bkey = b.resource_id.split(":").last
        if bkey == dkey
          book = b
        else
          ititle = (b.title + "_invalid_" + Time.now.utc.to_s)
          #http
          b.title=ititle
          ("Renamed duplicate book to #{ititle}").oputs
        end
      end
    else
      book = books.first
    end
    if book.nil?
      #add book using owner account
      #http
      book = Gdriver.root.create_spreadsheet(title)
      ("Created book #{title} at #{Time.now.utc.to_s}").oputs
    end
    #delete Sheet1 if there are other sheets
    #http
    if (sheets = book.worksheets).length>1
      sheet1 = sheets.select{|s| s.title == "Sheet1"}.first
      #http
      sheet1.delete if sheet1
    end
    #always make sure books have admin acl
    book.add_admin_acl
    return book
  end

  def Gbooker.find_or_create_by_dst_id(dst_id,account=nil)
    #creates by title, updates acl, updates dataset with url
    dst = dst_id.dst
    r = dst.requestor_id.r
    book = nil
    #http
    book = Gdriver.root.spreadsheet_by_url(dst.url) if dst.url
    #manually try 5 times to validate sheet since we can't just try again and again
    5.times.each do
      begin
        book.resource_id
        #if no error then break loop
        break
      rescue=>exc
        if book.nil? or exc.to_s.index('Invalid document id')
          book = Gbooker.find_or_create_by_title(dst.name,account)
          #if invalid doc then update url w new book and break loop
          dst.update_attributes(:url=>book.human_url)
          break
        end
      end
    end
    #add requestor write access
    book.update_acl(r.email)
    return book
  end
end

class Gsheeter

  def Gsheeter.max_cells
    400000
  end

  def Gsheeter.read(name,account=nil)
    sheet = Gsheeter.find_or_create_by_name(name,account)
    sheet.to_tsv
  end

  def Gsheeter.write(name,tsv,account=nil)
    sheet = Gsheeter.find_or_create_by_name(name,account)
    sheet.write(tsv)
  end

  def Gsheeter.find_or_create_by_name(name,account=nil,rows=100,cols=20)
    book_title,sheet_title = name.split("/")
    book = Gbooker.find_or_create_by_title(book_title,account)
    #http
    sheet = book.worksheets.select{|w| w.title==sheet_title}.first
    if sheet.nil?
      #http
      sheet = book.add_worksheet(sheet_title,rows,cols)
      ("Created sheet #{name} at #{Time.now.utc.to_s}").oputs
    end
    return sheet
  end

  def Gsheeter.find_or_create_by_dst_id(dst_id,account=nil)
    #creates by title, updates acl, updates dataset with url
    dst = dst_id.dst
    r = dst.requestor_id.r
    name = dst.name
    book_title,sheet_title = name.split("/")
    #make sure book exists and is assigned to this user
    book = r.find_or_create_gbook_by_title(book_title)
    #add admin write access
    sheet = Gsheeter.find_or_create_by_name(name)
    return sheet
  end

  def Gsheeter.read_by_job_id(job_id)
    #reading from job requires a "source" in the param_hash
    j = job_id.j
    r = j.requestor
    source = j.param_source
    book,sheet = source.split("/")
    #assume jobspec source if none given
    source = [r.jobspec_title,source].join("/") if sheet.nil?
    tsv = Gsheeter.find_or_create_by_name(source).to_tsv
    return tsv
  end

  def Gsheeter.read_by_dst_id(dst_id,account=nil)
    dst = dst_id.dst
    name = dst.name
    sheet = Gsheeter.find_or_create_by_name(name,account)
    output = sheet.to_tsv
    return output
  end

  def Gsheeter.write_by_dst_id(dst_id,tsv,account=nil)
    dst=dst_id.dst
    #see if this is a specific cell
    name = dst.name
    return false unless account
    #create temp tab, write data to it, checksum it against the source
    tempsheet = Gsheeter.find_or_create_by_name("#{name}_temp")
    tempsheet.write(tsv)
    #delete current sheet, replace it with temp one
    sheet = Gsheeter.find_or_create_by_name(dst.name)
    title = sheet.title
    #http
    sheet.delete
    begin
      tempsheet.rename(title)
    rescue
      #need this because sometimes it gets confused and tries to rename twice
    end
    "Write successful for #{write_name}".oputs
    return true
  end

  def Gsheeter.write_by_job_id(job_id)
    j = job_id.j
    r = j.requestor
    dest_name = if j.destination.split("/").length==1
                  "#{r.jobspec_title}#{"/"}#{j.destination}"
                else
                  j.destination
                end
    sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',dest_name)
    sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if sheet_dst.requestor_id.nil?
    account = Gdriver.get_worker_account
    #return false if there are no accounts available
    return false unless account
    Jobtracker.set_worker_args(j.worker['key'],{"account"=>account})
    #create temp tab, write data to it, checksum it against the source
    tempsheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',"#{dest_name}_temp")
    tempsheet_dst.update_attributes(:requestor_id=>r.id.to_s) if tempsheet_dst.requestor_id.nil?
    tempsheet = Gsheeter.find_or_create_by_dst_id(tempsheet_dst.id.to_s)
    #tsv is the second to last stage's output (the last is the write)
    tsv = j.tasks[j.prior_task]['output_dst_id'].dst.read
    tempsheet.write(tsv,true,job_id)
    #delete current sheet, replace it with temp one
    sheet = Gsheeter.find_or_create_by_name(dest_name,account)
    title = sheet.title
    #http
    sheet.delete
    tempsheet.title = title
    tempsheet.save
    sheet_dst.update_attributes(:url=>tempsheet.spreadsheet.human_url)
    "Write successful for #{dest_name}".oputs
    return true
  end
end
class GoogleDrive::Worksheet
  def to_tsv
    sheet = self
    #http
    sheet.rows.map{|r| r.join("\t")}.join("\n")
  end
  def write(tsv,check=true,job_id=nil)
    sheet = self
    tsvrows = tsv.split("\n")
    #no rows, no write
    return true if tsvrows.length==0
    headers = tsvrows.first.split("\t")
    #cap cells at 400k
    if (tsvrows.length*headers.length)>Gsheeter.max_cells
      raise "Too many cells in dataset"
    end
    batch_start = 0
    batch_length = 80
    rows_written = 0
    rowscols = nil
    #http
    curr_rows = sheet.num_rows
    curr_cols = sheet.num_cols
    pct_tens_complete =["0"]
    curr_pct_complete = "00"
    #make sure sheet is at least as big as necessary
    if tsvrows.length != curr_rows
      sheet.max_rows = tsvrows.length
      sheet.save
    end
    if headers.length != curr_cols
      sheet.max_cols = headers.length
      sheet.save
    end
    #write to sheet in batches of batch_length
    while batch_start < tsvrows.length
      batch_end = batch_start + batch_length
      tsvrows[batch_start..batch_end].each_with_index do |row,row_i|
        rowcols = row.split("\t")
        rowcols.each_with_index do |col_v,col_i|
          sheet[row_i+batch_start+1,col_i+1]= %{#{col_v}}
        end
      end
      sheet.save
      batch_start += (batch_length + 1)
      rows_written+=batch_length
      if batch_start>tsvrows.length+1
        if job_id
          newstatus = "100 pct written at #{Time.now.utc}"
          job_id.j.update_status(newstatus)
          newstatus.oputs
        end
        break
      else
        #pad digit
        curr_pct_complete = "%02d" % ((rows_written+1).to_f*100/tsvrows.length.to_f).round(0)
        if !pct_tens_complete.include?(curr_pct_complete.first)
          if job_id
            newstatus = "#{curr_pct_complete} pct written at #{Time.now.utc}"
            job_id.j.update_status(newstatus)
            newstatus.oputs
            pct_tens_complete << curr_pct_complete.first
          end
        end
      end
    end
    #checksum it against the source
    sheet.checksum(tsv) if check
    true
  end
  def checksum(tsv)
    sheet = self
    sheet.reload
    #loading remote data for checksum
    rem_tsv = sheet.to_tsv
    rem_table = rem_tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
    loc_table = tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
    re_col_vs = []
    errcnt = 0
    #checking cells
    loc_table.each_with_index do |loc_row,row_i|
      loc_row.each_with_index do |loc_v,col_i|
        rem_row = rem_table[row_i]
        if rem_row.nil?
          errcnt+=1
          "No Row #{row_i} for Write Dst".oputs
          break
        else
          rem_v = rem_table[row_i][col_i]
          if loc_v != rem_v
            if loc_v.starts_with?('rp') and rem_v.starts_with?('Rp')
              # some other math bs
              sheet[row_i+1,col_i+1] = %{'#{loc_v}}
              re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
            elsif (loc_v.to_s.count('e')==1 or loc_v.to_s.count('e')==0) and
              loc_v.to_s.sub('e','').to_i.to_s==loc_v.to_s.sub('e','').gsub(/\A0+/,"") #trim leading zeroes
              #this is a string in scentific notation, or a numerical string with a leading zero
              #GDocs handles this poorly, need to rewrite write_dst cells by hand with a leading apostrophe for text
              sheet[row_i+1,col_i+1] = %{'#{loc_v}}
              re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
            elsif loc_v.class==Float or loc_v.class==Fixnum
              if (loc_v - rem_v.to_f).abs>0.0001
                "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                errcnt+=1
              end
            elsif rem_v.class==Float or rem_v.class==Fixnum
              if (rem_v - loc_v.to_f).abs>0.0001
                "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                errcnt+=1
              end
            elsif loc_v.to_s.is_time?
              rem_time = begin
                           Time.parse(rem_v.to_s)
                         rescue
                           nil
                         end
              if rem_time.nil? || ((loc_v - rem_time).abs>1)
                "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                errcnt+=1
              end
            else
              #"loc_v=>#{loc_v.to_s},rem_v=>#{rem_v.to_s}".oputs
              if loc_v.force_encoding("UTF-8") != rem_v.force_encoding("UTF-8")
              #make sure it's not an ecoding issue
                "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                errcnt+=1
              end
            end
          end
        end
      end
    end
    if errcnt==0
      if re_col_vs.length>0
        sheet.save
        "rewrote:#{re_col_vs.to_s}".oputs
      else
        true
      end
    else
      raise "#{errcnt} errors found in checksum"
    end
  end
end

class Gtxter

  def Gtxter.post_by_job_id(job_id)
    #posts a file to the mobilize account,
    #posts the time and link to given cells
    j=job_id.j
    r=j.requestor
    title = %{#{r.name}_#{j.destination}}
    gztitle = [title,".gz"].join if !title.ends_with?(".gz")
    post_dst = Dataset.find_or_create_by_requestor_id_and_handler_and_name(r.id.to_s,'gtxter',gztitle)
    tsv = j.prior_task['output_dst_id'].dst.read.gsub("#","\t")
    account = Gdriver.get_worker_account
    #return false if there are no accounts available
    return false unless account
    Jobtracker.set_worker_args(j.worker_key,{"account"=>account})
    gzfile = Gtxter.post_by_gztitle(gztitle,tsv,account)
    post_dst.update_attributes(:url=>gzfile.human_url)
    #write
    return true
  end

  def Gtxter.post_by_gztitle(gztitle,tsv,account=nil)
    #expects a tsv, and a gz-suffixed file.
    #Gzips the tsv, uploads to gz-suffixed file on gdocs
    upload_file = %{#{Mobilize::Base.root}/tmp/#{gztitle}_upload.txt}
    File.open(upload_file,"w") {|f| f.print(tsv)}
    upload_filegz = upload_file + ".gz"
    #delete the upload file if already exists, gzip tsv one
    "rm -f #{upload_filegz};gzip #{upload_file}".bash
    old_rfile = Gdriver.txts.select{|t| t.title==gztitle}.first
    old_rfile.delete unless old_rfile.nil?
    #use base mobilize to ensure proper ownership
    rfile = Gdriver.root.upload_from_file(upload_filegz,gztitle, :convert=>false)
    "Posted file #{gztitle} at #{Time.now.utc.to_s}".oputs
    #add only workers - can't get file acl to work as expected
    Gfiler.add_worker_acl_by_title(gztitle)
    return rfile
  end
end
