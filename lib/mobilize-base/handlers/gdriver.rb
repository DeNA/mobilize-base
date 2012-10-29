class Gdriver

  def Gdriver.config
    Mobilize::Base.config('gdrive')[Mobilize::Base.env]
  end

  def Gdriver.owner_email
    Gdriver.config['owner']['email']
  end

  def Gdriver.password(email)
    if email == Gdriver.owner_email
      Gdriver.config['owner']['pw']
    else
      worker = Gdriver.workers(email)
      return worker['pw'] if worker
    end
  end

  def Gdriver.admins
    Gdriver.config['admins']
  end

  def Gdriver.workers(email=nil)
    if email.nil?
      Gdriver.config['workers']
    else
      Gdriver.workers.select{|w| w['email'] == email}.first
    end
  end

  def Gdriver.worker_emails
    Gdriver.workers.map{|w| w['email']}
  end

  def Gdriver.admin_emails
    Gdriver.admins.map{|w| w['email']}
  end

  #email management - used to make sure not too many emails get used at the same time
  def Gdriver.get_worker_email_by_job_id(job_id)
    active_emails = Resque::Mobilize.jobs('working').map{|j| j['email'] if j['email']}.compact
    Gdriver.workers.sort_by{rand}.each do |w|
      if !(active_emails.include?(w['email']))
        Resque::Mobilize.update_job_email(job_id,w['email'])
        return w
      end
    end
    #return false if none are available
    return false
  end

  def Gdriver.root(email=nil)
    email ||= Gdriver.owner_email
    pw = Gdriver.password(email)
    GoogleDrive.login(email,pw)
  end

  def Gdriver.files(email=nil)
    root = Gdriver.root(email)
    root.files
  end

  def Gdriver.books(email=nil)
    Gdriver.files(email).select{|f| f.class==GoogleDrive::Spreadsheet}
  end

end

class Gfiler
  def Gfiler.find_by_title(title,email=nil)
    Gdriver.files(email).select{|f| f.title==title}.first
  end

  def Gfiler.find_by_dst_id(dst_id,email=nil)
    dst = dst_id.dst
    Gfiler.find_by_title(dst.path,email)
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

  def Gfiler.update_acl_by_dst_id(dst_id,email,role="writer",edit_email=nil)
    dst = dst_id.dst
    Gfiler.update_acl_by_title(dst.path,email,role,edit_email)
  end

  def Gfiler.update_acl_by_title(title,email,role="writer",edit_email=nil)
    file = Gfiler.find_by_title(title,edit_email)
    raise "File #{title} not found" unless file
    file.update_acl(email,role)
  end
end

class GoogleDrive::File

  def add_worker_acl
    f = self
    return true if f.has_worker_acl?
    Gdriver.worker_emails.each do |a| 
      f.update_acl(a)
    end
  end

  def add_admin_acl
    f = self
    #admin includes workers
    return true if f.has_admin_acl?
    (Gdriver.admin_emails + Gdriver.worker_emails).each do |a| 
      f.update_acl(a)
    end
  end

  def has_admin_acl?
    f = self
    curr_emails = f.acls.map{|a| a.scope}.sort
    admin_emails = Gdriver.admin_emails.sort
    if (curr_emails & admin_emails) == admin_emails
      return true
    else
      return false
    end
  end

  def has_worker_acl?
    f = self
    curr_emails = f.acls.map{|a| a.scope}.sort
    worker_emails = Gdriver.worker_emails.sort
    if (curr_emails & worker_emails) == worker_emails
      return true
    else
      return false
    end
  end

  def update_acl(email,role="writer")
    f = self
    #need these flags for HTTP retries
    update_complete = false
    retries = 0
    #create req_acl hash to add to current acl
    if entry = f.acl_entry(email)
      if [nil,"none","delete"].include?(role)
        f.acl.delete(entry)
      elsif entry.role != role and ['reader','writer','owner'].include?(role)
        entry.role=role
        f.acl.update_role(entry,entry.role,notify=false)
      elsif !['reader','writer','owner'].include?(role)
        raise "Invalid role #{role}"
      end
    else
      f.acl.push({:scope_type=>"user",:scope=>email,:role=>role},notify=false)
    end
    return true
  end
  def acls
    f = self
    f.acl.to_enum.to_a
  end
  def acl_entry(email)
    f = self
    curr_acls = f.acls
    curr_emails = curr_acls.map{|a| a.scope}
    f.acls.select{|a| ['group','user'].include?(a.scope_type) and a.scope == email}.first
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

  def Gbooker.find_or_create_by_title(title,email)
    books = Gdriver.books(email).select{|b| b.title==title}
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
          #delete the invalid book
          b.delete
          ("Deleted duplicate book #{title}").oputs
        end
      end
    else
      book = books.first
    end
    if book.nil?
      #add book using owner email
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

  def Gbooker.find_or_create_by_dst_id(dst_id,email=nil)
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
          book = Gbooker.find_or_create_by_title(dst.name,email)
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

  def Gsheeter.read(name,email=nil)
    sheet = Gsheeter.find_or_create_by_name(name,email)
    sheet.to_tsv
  end

  def Gsheeter.write(name,tsv,email=nil)
    sheet = Gsheeter.find_or_create_by_name(name,email)
    sheet.write(tsv)
  end

  def Gsheeter.find_or_create_by_name(name,email=nil,rows=100,cols=20)
    book_title,sheet_title = name.split("/")
    book = Gbooker.find_or_create_by_title(book_title,email)
    #http
    sheet = book.worksheets.select{|w| w.title==sheet_title}.first
    if sheet.nil?
      #http
      sheet = book.add_worksheet(sheet_title,rows,cols)
      ("Created sheet #{name} at #{Time.now.utc.to_s}").oputs
    end
    return sheet
  end

  def Gsheeter.find_or_create_by_dst_id(dst_id,email=nil)
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
    j = Job.find(job_id)
    r = j.requestor
    #reserve email account for read
    email = Gdriver.get_worker_email_by_job_id(job_id)
    return false unless email
    source = j.param_source
    book,sheet = source.split("/")
    #assume jobspec source if none given
    source = [r.jobspec_title,source].join("/") if sheet.nil?
    tsv = Gsheeter.find_or_create_by_name(source,email).to_tsv
    return tsv
  end

  def Gsheeter.read_by_dst_id(dst_id,email=nil)
    dst = dst_id.dst
    name = dst.name
    sheet = Gsheeter.find_or_create_by_name(name,email)
    output = sheet.to_tsv
    return output
  end

  def Gsheeter.write_by_dst_id(dst_id,tsv,email=nil)
    dst=dst_id.dst
    #see if this is a specific cell
    name = dst.name
    return false unless email
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
    email = Gdriver.get_worker_email_by_job_id(job_id)
    #return false if there are no emails available
    return false unless email
    #create temp tab, write data to it, checksum it against the source
    tempsheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',"#{dest_name}_temp")
    tempsheet_dst.update_attributes(:requestor_id=>r.id.to_s) if tempsheet_dst.requestor_id.nil?
    tempsheet = Gsheeter.find_or_create_by_dst_id(tempsheet_dst.id.to_s)
    #tsv is the second to last stage's output (the last is the write)
    tsv = j.tasks[j.prior_task]['output_dst_id'].dst.read
    tempsheet.write(tsv,true,job_id)
    #delete current sheet, replace it with temp one
    sheet = Gsheeter.find_or_create_by_name(dest_name,email)
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
