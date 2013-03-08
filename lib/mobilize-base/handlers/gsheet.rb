module Mobilize
  module Gsheet

    def Gsheet.config
      Base.config('gsheet')
    end

    def Gsheet.max_cells
      Gsheet.config['max_cells']
    end

    # converts a path to a url in the context of gsheet and username
    def Gsheet.url(path,username)
      if path.split("/").length == 2
        #user has specified path to a sheet
        return "gsheet://#{path}"
      else
        #user has specified a sheet
        #in their runner
        return "gsheet://Runner_#{username}/#{path}"
      end
    end

    def Gsheet.write(path,tsv,gdrive_slot)
      sheet = Gsheet.find_or_create_by_path(path,gdrive_slot)
      sheet.write(tsv,Gdrive.owner_name)
    end

    def Gsheet.find_by_path(path,gdrive_slot)
      book_path,sheet_name = path.split("/")
      book = Gbook.find_by_path(book_path,gdrive_slot)
      return book.worksheet_by_title(sheet_name) if book
    end

    def Gsheet.find_or_create_by_path(path,gdrive_slot,rows=100,cols=20)
      book_path,sheet_name = path.split("/")
      book = Gbook.find_or_create_by_path(book_path,gdrive_slot)
      sheet = book.worksheet_by_title(sheet_name)
      if sheet.nil?
        sheet = book.add_worksheet(sheet_name,rows,cols)
        ("Created gsheet #{path} at #{Time.now.utc.to_s}").oputs
      end
      Dataset.find_or_create_by_handler_and_path("gsheet",path)
      return sheet
    end

    def Gsheet.write_temp(stage,gdrive_slot,tsv)
      target_path = stage.params['target']
      sheet_name = target_path.split("/").last
      temp_path = [stage_path.gridsafe,sheet_name].join("/")
      #find and delete temp sheet, if any
      temp_sheet = Gsheet.find_by_path(temp_path,gdrive_slot)
      temp_sheet.delete if temp_sheet
      #write data to temp sheet
      temp_sheet = Gsheet.find_or_create_by_path(temp_path,gdrive_slot)
      #this step has a tendency to fail; if it does,
      #don't fail the stage, mark it as false
      begin
        temp_sheet.write(tsv,Gdrive.owner_name)
      rescue
        return nil
      end
      temp_sheet.check_and_fix(tsv)
      temp_sheet
    end

    def Gsheet.write_target(stage,gdrive_slot)
      #get tsv to write from stage
      source_dst = stage.source_dsts(gdrive_slot).first
      tsv = source_dst.read(user.name)
      #write to temp sheet first, to ensure google compatibility
      #and fix any discrepancies due to spradsheet assumptions
      temp_sheet = Gsheet.write_temp(stage,gdrive_slot,tsv)
      #try to find target sheet
      user = stage.job.runner.user
      target_path = stage.params['target']
      target_path = "#{stage.job.runner.title}/#{target_path}" unless target_path.index("/")
      target_sheet = Gsheet.find_by_path(target_path,gdrive_slot)
      unless target_sheet
        #only give the user edit permissions if they're the ones
        #creating it
        target_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
        target_sheet.spreadsheet.update_acl(user.email,"writer") unless target_sheet.spreadsheet.acl_entry(user.email).ie{|e| e and e.role=="owner"}
        target_sheet.delete_sheet1
      end
      target_sheet.merge(temp_sheet,user.name)
      #pass it crop param to determine whether to shrink target sheet to fit data
      #default is yes
      crop = stage.params['crop'] || true
      target_sheet.merge(temp_sheet,user.name, crop)
      #delete the temp sheet's book
      temp_sheet.spreadsheet.delete
      #update status
      status = "Write successful for #{target_path}"
      stage.update_status(status)
      status
    end

    def Gsheet.write_by_stage_path(stage_path)
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      #return blank response if there are no slots available
      return nil unless gdrive_slot
      stage = Stage.where(:path=>stage_path).first
      begin
        stdout = Gsheet.write_target(stage,gdrive_slot)
        signal = 0
      rescue => exc
        stderr = [exc.to_s,"\n",exc.backtrace.to_s].join
        Dataset.write_by_url(err_url,exc.to_s,Gdrive.owner_name)
        signal = 500
      end
      #return urls from write
      out_url = Dataset.write_by_url(out_url,stdout.to_s,Gdrive.owner_name)
      err_url = Dataset.write_by_url(err_url,stderr.to_s,Gdrive.owner_name)
      return {'out_url'=>out_url, 'err_url'=>err_url, 'signal' => signal}
    end
  end
end
