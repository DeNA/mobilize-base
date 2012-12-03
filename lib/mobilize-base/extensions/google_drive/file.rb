module GoogleDrive
  class File

    def add_worker_acl
      f = self
      return true if f.has_worker_acl?
      Mobilize::Gdrive.worker_emails.each do |a| 
        f.update_acl(a)
      end
    end

    def add_admin_acl
      f = self
      #admin includes workers
      return true if f.has_admin_acl?
      (Mobilize::Gdrive.admin_emails + Mobilize::Gdrive.worker_emails).each do |a| 
        f.update_acl(a)
      end
    end

    def has_admin_acl?
      f = self
      curr_emails = f.acls.map{|a| a.scope}.sort
      admin_emails = Mobilize::Gdrive.admin_emails.sort
      if (curr_emails & admin_emails) == admin_emails
        return true
      else
        return false
      end
    end

    def has_worker_acl?
      f = self
      curr_emails = f.acls.map{|a| a.scope}.sort
      worker_emails = Mobilize::Gdrive.worker_emails.sort
      if (curr_emails & worker_emails) == worker_emails
        return true
      else
        return false
      end
    end

    def update_acl(email,role="writer")
      f = self
      #need these flags for HTTP retries
      #create req_acl hash to add to current acl
      if entry = f.acl_entry(email)
        if [nil,"none","delete"].include?(role)
          f.acl.delete(entry)
        elsif entry.role != role and ['reader','writer','owner'].include?(role)
          entry.role=role
          f.acl.update_role(entry,entry.role)
        elsif !['reader','writer','owner'].include?(role)
          raise "Invalid role #{role}"
        end
      else
        f.acl.push({:scope_type=>"user",:scope=>email,:role=>role})
      end
      return true
    end
    def acls
      f = self
      f.acl.to_enum.to_a
    end
    def acl_entry(email)
      f = self
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
end
