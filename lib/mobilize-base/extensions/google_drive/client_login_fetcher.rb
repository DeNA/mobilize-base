module GoogleDrive
  class ClientLoginFetcher
    def request_raw(method, url, data, extra_header, auth)
      clf = self
      #this is patched to handle server errors due to http chaos
      uri = URI.parse(url)
      response = nil
      attempts = 0
      sleep_time = nil
      #try 5 times to make the call
      while (response.nil? or response.code.starts_with?("5")) and attempts < Mobilize::Gdrive.max_api_retries
        #instantiate http object, set params
        http = @proxy.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        #set 600  to allow for large downloads
        http.read_timeout = 600
        response = begin
                     puts "Gdrive API #{method.to_s}: #{uri.to_s} #{extra_header.to_s}"
                     clf.http_call(http, method, uri, data, extra_header, auth)
                   rescue
                     #timeouts etc.
                     nil
                   end
        if response.nil? or response.code.starts_with?("4")
          attempts +=1
        elsif
          if response.code.starts_with?("5")
            #wait 10 seconds times number of attempts squared in case of error
            sleep_time = 10 * (attempts*attempts)
            attempts += 1
            puts "Sleeping for #{sleep_time.to_s} due to #{response.body}"
            sleep sleep_time
          end
        end
      end
      raise "No response after 20 attempts" if response.nil?
      raise response.body if response.code.ie{|rcode| rcode.starts_with?("4") or rcode.starts_with?("5")}
      return response
    end
    def http_call(http, method, uri, data, extra_header, auth)
      http.read_timeout = 600
      http.start() do
        path = uri.path + (uri.query ? "?#{uri.query}" : "")
        header = auth_header(auth).merge(extra_header)
        if method == :delete || method == :get
          http.__send__(method, path, header)
        else
          http.__send__(method, path, data, header)
        end
      end
    end
  end
end
