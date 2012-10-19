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
