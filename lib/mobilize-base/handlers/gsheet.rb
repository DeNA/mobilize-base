module Mobilize
  module Gsheet

    def Gsheet.max_cells
      400000
    end

    def Gsheet.read(name,email=nil)
      sheet = Gsheet.find_or_create_by_name(name,email)
      sheet.to_tsv
    end

    def Gsheet.write(name,tsv,email=nil)
      sheet = Gsheet.find_or_create_by_name(name,email)
      sheet.write(tsv)
    end

    def Gsheet.find_all_by_name(name,email)
      book_title,sheet_title = name.split("/")
      books = Gdrive.books(email,{"title"=>book_title,"title-exact"=>"true"})
      sheets = books.map{|b| b.worksheets}.flatten.select{|w| w.title == sheet_title }
      sheets
    end

    def Gsheet.find_or_create_by_name(name,email=nil,rows=100,cols=20)
      book_title,sheet_title = name.split("/")
      book = Gbook.find_or_create_by_title(book_title,email)
      #http
      sheet = book.worksheets.select{|w| w.title==sheet_title}.first
      if sheet.nil?
        #http
        sheet = book.add_worksheet(sheet_title,rows,cols)
        ("Created sheet #{name} at #{Time.now.utc.to_s}").oputs
      end
      return sheet
    end

    def Gsheet.find_or_create_by_dst_id(dst_id,email=nil)
      #creates by title, updates acl, updates dataset with url
      dst = Dataset.find(dst_id)
      r = Requestor.find(dst.requestor_id)
      name = dst.name
      book_title,sheet_title = name.split("/")
      #make sure book exists and is assigned to this user
      r.find_or_create_gbook_by_title(book_title,email)
      #add admin write access
      sheet = Gsheet.find_or_create_by_name(name)
      sheet_title = nil
      return sheet
    end

    def Gsheet.read_by_dst_id(dst_id,email=nil)
      dst = Dataset.find(dst_id)
      name = dst.name
      sheet = Gsheet.find_or_create_by_name(name,email)
      output = sheet.to_tsv
      return output
    end

    def Gsheet.read_by_job_id(job_id)
      j = Job.find(job_id)
      #reserve email account for read
      email = Gdrive.get_worker_email_by_mongo_id(job_id)
      return false unless email
      #pull tsv from cache
      j.dataset_array.first.read_cache
    end

    def Gsheet.write_by_dst_id(dst_id,tsv,email=nil)
      dst = Dataset.find(dst_id)
      #see if this is a specific cell
      name = dst.name
      return false unless email
      #create temp tab, write data to it, checksum it against the source
      temp_sheet = Gsheet.find_or_create_by_name("#{name}_temp")
      temp_sheet.write(tsv)
      #delete current sheet, replace it with temp one
      sheet = Gsheet.find_or_create_by_name(dst.name)
      title = sheet.title
      #http
      sheet.delete
      begin
        temp_sheet.rename(title)
      rescue
        #need this because sometimes it gets confused and tries to rename twice
      end
      "Write successful for #{write_name}".oputs
      return true
    end

    def Gsheet.write_by_job_id(job_id)
      j = Job.find(job_id)
      r = j.requestor
      dest_name = if j.destination.split("/").length==1
                    "#{r.jobspec_title}#{"/"}#{j.destination}"
                  else
                    j.destination
                  end
      sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheet',dest_name)
      sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if sheet_dst.requestor_id.nil?
      email = Gdrive.get_worker_email_by_mongo_id(job_id)
      #return false if there are no emails available
      return false unless email
      #create temp tab, write data to it, checksum it against the source
      temp_sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheet',"#{dest_name}_temp")
      temp_sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if temp_sheet_dst.requestor_id.nil?
      temp_sheet = Gsheet.find_or_create_by_name(temp_sheet_dst.name,email)
      #tsv is the prior task's output
      tsv = j.task_output_dsts[j.task_idx-1].read
      temp_sheet.write(tsv,true,job_id)
      #delete current sheet, replace it with temp one
      sheet = Gsheet.find_or_create_by_name(dest_name,email)
      title = sheet.title
      #http
      sheet.delete
      temp_sheet.title = title
      temp_sheet.save
      sheet_dst.update_attributes(:url=>temp_sheet.spreadsheet.human_url)
      "Write successful for #{dest_name}".oputs
      return true
    end
  end
end
