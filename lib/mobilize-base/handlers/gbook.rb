module Mobilize
  module Gbook
    def Gbook.find_all_by_path(path,gdrive_slot)
      Gdrive.books(gdrive_slot,{"title"=>path,"title-exact"=>"true"})
    end

    def Gbook.find_by_http_url(http_url,gdrive_slot)
      key = http_url.split("key=").last.split("#").first
      Gdrive.root(gdrive_slot).spreadsheet_by_key(key)
    end

    def Gbook.find_by_path(path,gdrive_slot)
      #first try to find a dataset with the URL
      dst = Dataset.find_by_handler_and_path('gbook',path)
      if dst and dst.http_url.to_s.length>0
        book = Gbook.find_by_http_url(dst.http_url,gdrive_slot)
      else
        books = Gbook.find_all_by_path(path,gdrive_slot)
        dst = Dataset.find_or_create_by_handler_and_path('gbook',path)
        book = nil
        if books.length>1 and dst.http_url.to_s.length>0
          #some idiot process or malicious user created a duplicate book.
          #Fix by deleting all but the one with dst entry's key
          dkey = dst.http_url.split("key=").last
          books.each do |b|
            bkey = b.resource_id.split(":").last
            if bkey == dkey
              book = b
            else
              #delete the invalid book
              b.delete
              ("Deleted duplicate book #{path}").oputs
            end
          end
        else
          #If it's a new dst or if there are multiple books
          #take the first
          book = books.first
          dst.update_attributes(:http_url=>book.http_url)
        end
      end
      return book
    end
    def Gbook.find_or_create_by_path(path,gdrive_slot)
      book = Gbook.find_by_path(path,gdrive_slot)
      dst = Dataset.find_or_create_by_handler_and_path('gbook',path)
      if book.nil?
        #always use owner email to make sure all books are owned by owner account
        book = Gdrive.root(Gdrive.owner_email).create_spreadsheet(path)
        ("Created book #{path} at #{Time.now.utc.to_s}; Access at #{book.human_url}").oputs
      end
      #always make sure book dataset http URL is up to date
      #and that book has admin acl
      dst.update_attributes(:http_url=>book.human_url)
      book.add_admin_acl
      return book
    end
  end
end
