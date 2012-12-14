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
      while (response.nil? or response.code.ie{|rcode| rcode.starts_with?("4") or rcode.starts_with?("5")}) and attempts < 5
        #instantiate http object, set params
        http = @proxy.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        #set 600  to allow for large downloads
        http.read_timeout = 600
        response = begin
                     clf.http_call(http, method, uri, data, extra_header, auth)
                   rescue
                     #timeouts etc.
                     nil
                   end
        if response.nil?
          attempts +=1
        else
          if response.code.ie{|rcode| rcode.starts_with?("4") or rcode.starts_with?("5")}
            if response.body.downcase.index("rate limit") or response.body.downcase.index("captcha")
              if sleep_time
                sleep_time = sleep_time * attempts
              else
                sleep_time = (rand*100).to_i
              end
            else
              sleep_time = 10
            end
            attempts += 1
            puts "Sleeping for #{sleep_time.to_s} due to #{response.body}"
            sleep sleep_time
          end
        end
      end
      raise "No response after 5 attempts" if response.nil?
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
