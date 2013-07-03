module Mobilize
  class User
    include Mongoid::Document
    include Mongoid::Timestamps
    field :active, type: Boolean
    field :name, type: String
    field :ssh_public_key, type: String
    field :last_run, type: Time

    def User.find_or_create_by_name(name)
      u = User.where(:name => name).first
      u = User.create(:name => name) unless u
      return u
    end

    def email
      u = self
      "#{u.name}@#{Gdrive.domain}"
    end

    def runner
      u = self
      Runner.find_or_create_by_path(u.runner_path)
    end

    def jobs(jname=nil)
      u = self
      return u.runner.jobs
    end

    #identifies the server which should process this user's jobs
    #determined by available servers in config/deploy/<env>
    #otherwise, localhost
    def resque_server
      u = self
      deploy_file_path = "#{Base.root}/config/deploy/#{Base.env}.rb"
      result = begin
                 server_line = File.readlines(deploy_file_path).select{|l| l.strip.starts_with?("role ")}.first
                 #reject arguments that start w symbols
                 server_strings = server_line.split(",")[1..-1].reject{|t| t.strip.starts_with?(":")}
                 servers = server_strings.map{|ss| ss.gsub("'","").gsub('"','').strip}
                 server_i = u.name.to_md5.gsub(/[^0-9]/,'').to_i % servers.length
                 servers[server_i]
               rescue
                 #default to self if this doesn't work
                 "127.0.0.1"
               end
      result
    end

    def runner_path
      u = self
      prefix = "Runner_"
      suffix = (Base.env == 'production' ? "" : "(#{Base.env})")
      title = [prefix,u.name,suffix,"/jobs"].join
      return title
    end
  end
end
