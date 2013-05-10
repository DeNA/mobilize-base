module GoogleDrive
  class Acl
    def update_role(entry, role) #:nodoc:
      #do not send email notifications
      url_suffix = "?send-notification-emails=false"
      header = {"GData-Version" => "3.0", "Content-Type" => "application/atom+xml"}
      doc = @session.request(
          :put, %{#{entry.edit_url}#{url_suffix}}, :data => entry.to_xml(), :header => header, :auth => :writely)

      entry.params = entry_to_params(doc.root)
      return entry
    end

    def push(entry)
      #do not send email notifications
      entry = AclEntry.new(entry) if entry.is_a?(Hash)
      url_suffix = ((@acls_feed_url.index("?") ? "&" : "?") + "send-notification-emails=false")
      header = {"GData-Version" => "3.0", "Content-Type" => "application/atom+xml"}
      doc = @session.request(:post, "#{@acls_feed_url}#{url_suffix}", :data => entry.to_xml(), :header => header, :auth => :writely)
      entry.params = entry_to_params(doc.root)
      @acls.push(entry)
      return entry
    end
  end
end
