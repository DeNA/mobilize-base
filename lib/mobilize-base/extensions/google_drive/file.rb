module GoogleDrive
  class File

    def add_worker_acl
      f = self
      email = "#{Mobilize::Gdrive.worker_group_name}@#{Mobilize::Gdrive.domain}"
      f.update_acl(email,"group")
    end

    def add_admin_acl
      f = self
      email = "#{Mobilize::Gdrive.admin_group_name}@#{Mobilize::Gdrive.domain}"
      f.update_acl(email,"group")
      #if adding acl ,must currently add workers as well
      f.add_worker_acl
    end

    def read(user_name)
      f = self
      entry = f.acl_entry("#{user_name}@#{Mobilize::Gdrive.domain}")
      if entry and ['reader','writer','owner'].include?(entry.role)
        f.download_to_string
      else
        raise "User #{user_name} is not allowed to read #{f.title}"
      end
    end

    def update_acl(email,scope_type="user",role="writer")
      f = self
      #need these flags for HTTP retries
      #create req_acl hash to add to current acl
      if entry = f.acl_entry(email)
        if [nil,"none","delete"].include?(role)
          f.acl.delete(entry)
        elsif entry.role != role and ['reader','writer','owner'].include?(role)
          entry.role=role
          f.acl.update_role(entry,entry.role)
          if entry.role != role
            #for whatever reason
            f.acl.delete(entry)
            f.acl.push({:scope_type=>scope_type,:scope=>email,:role=>role})
          end
        elsif !['reader','writer','owner'].include?(role)
          raise "Invalid role #{role}"
        end
      else
        begin
          f.acl.push({:scope_type=>scope_type,:scope=>email,:role=>role})
        rescue => exc
          raise exc unless exc.to_s.index("already has access")
        end
      end
      return true
    end
    def acls
      f = self
      f.acl.to_enum.to_a
    end
    def acl_entry(email)
      f = self
      f.acls.select{|a| ['group','user'].include?(a.scope_type) and a.scope and a.scope == email}.first
    end
    def entry_hash
      f = self
      dfe_xml = f.document_feed_entry.to_xml
      result = Nokogiri::XML(dfe_xml)
      { result.root.name.to_sym => Hash.xml_node_to_hash(result.root)}[:entry]
    end
  end
end
