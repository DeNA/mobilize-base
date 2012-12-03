module Mobilize
  module Gsheet

    def Gsheet.max_cells
      400000
    end

    def Gsheet.write(path,tsv,gdrive_slot)
      sheet = Gsheet.find_or_create_by_path(path,gdrive_slot)
      sheet.write(tsv)
    end

    def Gsheet.find_by_path(path,gdrive_slot)
      book_title,sheet_title = path.split("/")
      book = Gdrive.books(gdrive_slot,{"title"=>book_title,"title-exact"=>"true"}).first
      return book.worsheet_by_title(sheet_title) if book
    end

    def Gsheet.find_or_create_by_path(path,gdrive_slot,rows=100,cols=20)
      book_title,sheet_title = path.split("/")
      book = Gbook.find_or_create_by_title(book_title,gdrive_slot)
      #http
      sheet = book.worksheet_by_title(sheet_title)
      if sheet.nil?
        #http
        sheet = book.add_worksheet(sheet_title,rows,cols)
        ("Created gsheet #{path} at #{Time.now.utc.to_s}").oputs
      end
      return sheet
    end

    def Gsheet.read_by_task_path(task_path)
      t = Task.where(:path=>task_path)
      #reserve gdrive_slot account for read
      gdrive_slot = Gdrive.slot_worker_by_path(t.path)
      return false unless gdrive_slot
      gsheet_path = t.params.first
      Gsheet.find_by_path(gsheet_path,gdrive_slot).to_tsv
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

    def Gsheet.write_by_task_path(task_path)
      j = Job.find(job_id)
      r = j.requestor
      dest_name = if j.destination.split("/").length==1
                    "#{r.runner_title}#{"/"}#{j.destination}"
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
