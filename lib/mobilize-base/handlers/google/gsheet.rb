module Mobilize
  module Gsheet

    def Gsheet.config
      Base.config('gsheet')
    end

    def Gsheet.max_cells
      Gsheet.config['max_cells']
    end

    # converts a source path or target path to a dst in the context of handler and stage
    def Gsheet.path_to_dst(path,stage_path,gdrive_slot)
      s = Stage.where(:path=>stage_path).first
      params = s.params
      target_path = params['target']
      #if this is the target, it doesn't have to exist already
      is_target = true if path == target_path
      #don't need the ://
      path = path.split("://").last if path.index("://")
      if path.split("/").length == 2
        if is_target or Gsheet.find_by_path(path,gdrive_slot)
          #user has specified path to a sheet
          return Dataset.find_or_create_by_url("gsheet://#{path}")
        else
          raise "unable to find #{path}"
        end
      else
        #user has specified a sheet
        runner_title = stage_path.split("/").first
        r = Runner.find_by_title(runner_title)
        if is_target or r.gbook(gdrive_slot).worksheets.map{|w| w.title}.include?(path)
          handler = "gsheet"
          path = "#{runner_title}/#{path}"
        elsif Gfile.find_by_path(path,gdrive_slot)
          handler = "gfile"
          path = "#{path}"
        else
          raise "unable to find #{path}"
        end
        return Dataset.find_or_create_by_url("#{handler}://#{path}")
      end
    end

    def Gsheet.read_by_dataset_path(dst_path,user_name,*args)
      #expects gdrive slot as first arg, otherwise chooses random
      gdrive_slot = args.to_a.first
      sheet = Gsheet.find_by_path(dst_path,gdrive_slot)
      sheet.read(user_name) if sheet
    end

    def Gsheet.write_by_dataset_path(dst_path,tsv,user_name,*args)
      #expects gdrive slot as first arg, otherwise chooses random
      gdrive_slot,crop = args
      crop ||= true
      Gsheet.write_target(dst_path,tsv,user_name,gdrive_slot,crop)
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
      #try to guess the sheet case
      sheet = book.worksheet_by_title(sheet_name) ||
              book.worksheet_by_title(sheet_name.downcase) ||
              book.worksheet_by_title(sheet_name.capitalize)
      if sheet.nil?
        sheet = book.add_worksheet(sheet_name,rows,cols)
        ("Created gsheet #{path} at #{Time.now.utc.to_s}").oputs
      end
      Dataset.find_or_create_by_handler_and_path("gsheet",path)
      return sheet
    end

    def Gsheet.write_temp(target_path,gdrive_slot,tsv)
      #find and delete temp sheet, if any
      temp_book_title = target_path.downcase.alphanunderscore
      #create book and sheet
      temp_book = Gdrive.root(gdrive_slot).create_spreadsheet(temp_book_title)
      #add admin acl so we can look at it if it fails
      temp_book.add_admin_acl
      rows, cols = tsv.split("\n").ie{|t| [t.length,t.first.split("\t").length]}
      temp_sheet = temp_book.add_worksheet("temp",rows,cols)
      #this step has a tendency to fail; if it does,
      #don't fail the stage, mark it as false
      begin
        gdrive_user = gdrive_slot.split("@").first
        temp_sheet.write(tsv,gdrive_user)
      rescue
        return nil
      end
      temp_sheet.check_and_fix(tsv)
      temp_sheet
    end

    def Gsheet.write_target(target_path,tsv,user_name,gdrive_slot,crop=true)
      #write to temp sheet first, to ensure google compatibility
      #and fix any discrepancies due to spradsheet assumptions
      temp_sheet = Gsheet.write_temp(target_path,gdrive_slot,tsv)
      #try to find target sheet
      target_sheet = Gsheet.find_by_path(target_path,gdrive_slot)
      u = User.where(:name=>user_name).first
      unless target_sheet
        #only give the user edit permissions if they're the ones
        #creating it
        target_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
        target_sheet.spreadsheet.update_acl(u.email) unless target_sheet.spreadsheet.acl_entry(u.email).ie{|e| e and e.role=="owner"}
        target_sheet.delete_sheet1
      end
      #pass it crop param to determine whether to shrink target sheet to fit data
      #default is yes
      target_sheet.merge(temp_sheet,user_name,crop)
      #delete the temp sheet's book
      temp_sheet.spreadsheet.delete
      target_sheet
    end

    def Gsheet.write_by_stage_path(stage_path)
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      #return blank response if there are no slots available
      return nil unless gdrive_slot
      s = Stage.where(:path=>stage_path).first
      u = s.job.runner.user
      crop = s.params['crop'] || true
      retries = 0
      stdout,stderr = []
      while stdout.nil? and stderr.nil? and retries < Gdrive.max_file_write_retries
        begin
          #get tsv to write from stage
          source = s.sources(gdrive_slot).first
          raise "Need source for gsheet write" unless source
          tsv = source.read(u.name,gdrive_slot)
          raise "No data source found for #{source.url}" unless tsv
          tsv_row_count = tsv.to_s.split("\n").length
          tsv_col_count = tsv.to_s.split("\n").first.to_s.split("\t").length
          tsv_cell_count = tsv_row_count * tsv_col_count
          if tsv_cell_count > Gsheet.max_cells
            raise "Too many datapoints; you have #{tsv_cell_count.to_s}, max is #{Gsheet.max_cells.to_s}"
          end
          stdout = if tsv_row_count == 0
                     #soft error; no data to write. Stage will complete.
                     "Write skipped for #{s.target.url}"
                   else
                     Dataset.write_by_url(s.target.url,tsv,u.name,gdrive_slot,crop)
                     #update status
                     "Write successful for #{s.target.url}"
                   end
          Gdrive.unslot_worker_by_path(stage_path)
          stderr = nil
          s.update_status(stdout)
          signal = 0
        rescue => exc
          if retries < Gdrive.max_file_write_retries
            retries +=1
            stdout = nil
            stderr = [exc.to_s,"\n",exc.backtrace.join("\n")].join
            signal = 500
            sleep Gdrive.file_write_retry_delay
          end
        end
      end
      return {'out_str'=>stdout, 'err_str'=>stderr, 'signal' => signal}
    end
  end
end
