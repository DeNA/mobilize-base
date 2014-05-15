module Mobilize
  module Gbook
    def Gbook.find_all_by_path(path,gdrive_slot)
      Gdrive.books(gdrive_slot,{"title"=>path,"title-exact"=>"true"})
    end

    def Gbook.find_by_http_url(http_url,gdrive_slot)
      Gdrive.root(gdrive_slot).spreadsheet_by_url(http_url)
    end

    def Gbook.find_by_path(path,gdrive_slot)
      #first try to find a dataset with the URL
      dst = Dataset.find_by_handler_and_path('gbook',path)
      if dst and dst.http_url.to_s.length>0
        book = Gbook.find_by_http_url(dst.http_url,gdrive_slot)
        if book
          return book
        else
          raise "Could not find book #{path} with url #{dst.http_url}, please check dataset"
        end
      end
      #try to find books by title
      books = Gbook.find_all_by_path(path,gdrive_slot)
      #sort by publish date; if entry hash retrieval fails (as it does)
      #assume the book was published now
      book = books.sort_by{|b| begin b.entry_hash[:published];rescue;Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z");end;}.first
      if book
        #we know dataset will have blank url since it wasn't picked up above
        dst = Dataset.find_or_create_by_handler_and_path('gbook',path)
        api_url = book.human_url.split("&").first
        dst.update_attributes(:http_url=>api_url)
      end
      return book
    end

    def Gbook.find_or_create_by_path(path,gdrive_slot)
      book = Gbook.find_by_path(path,gdrive_slot)
      if book.nil?
        #always use owner email to make sure all books are owned by owner account
        book = Gdrive.root(Gdrive.owner_email).create_spreadsheet(path)
        ("Created book #{path} at #{Time.now.utc.to_s}; Access at #{book.human_url}").oputs
        #check to make sure the dataset has a blank url; if not, error out
        dst = Dataset.find_or_create_by_handler_and_path('gbook',path)
        if dst.http_url.to_s.length>0
          #add acls to book regardless
          book.add_admin_acl
          raise "Book #{path} is already assigned to #{dst.http_url}; please update the record with #{book.human_url}"
        else
          api_url = book.human_url.split("&").first
          dst.update_attributes(:http_url=>api_url)
          book.add_admin_acl
        end
      end
      return book
    end
  end
end
