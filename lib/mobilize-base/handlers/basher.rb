class Basher

  def Basher.hosts
    if File.exists?("config/mobilize/hosts.yml")
      YAML.load_file("config/mobilize/hosts.yml")
    else
      #local by default
      {'local'=>{'host'=>'127.0.0.1'}}
    end
  end

  def Basher.gate_sh(gateid,hostid,commands,except=true,errlog=nil)
    ghost,gkeys,gport,guser = Basher.hosts[gateid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    gopts = {:port=>(gport||22),:keys=>gkeys}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    return Net::SSH::Gateway.sh(ghost,guser,host,huser,commands,gopts,hopts,except,errlog)
  end

  #Socket.gethostname is localhost
  def Basher.gate_write(gateid,hostid,data,topath,binary=false)
    ghost,gkeys,gport,guser = Basher.hosts[gateid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    gopts = {:port=>(gport||22),:keys=>gkeys}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    frompath = Basher.tmpfile(data,binary)
    Net::SSH::Gateway.sync(ghost,guser,frompath,topath,host,gopts,{},hopts,Socket.gethostname,ENV['LOGNAME'],huser)
    "rm #{frompath}".bash
    return true
  end

  def Basher.gate_scp(gateid,hostid,frompath,topath)
    ghost,gkeys,gport,guser = Basher.hosts[gateid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    gopts = {:port=>(gport||22),:keys=>gkeys}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    return Net::SSH::Gateway.sync(ghost,guser,frompath,topath,host,gopts,{},hopts,Socket.gethostname,ENV['LOGNAME'],huser)
  end

  def Basher.write(hostid,data,topath,binary=false)
    return Basher.gate_write('gateway',hostid,data,topath,binary) if Socket.needs_gateway?
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    frompath = Basher.tmpfile(data,binary)
    Basher.scp(hostid,frompath,topath)
    "rm #{frompath}".bash
    return true
  end

  def Basher.scp(hostid,frompath,topath)
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    if ['localhost','127.0.0.1'].include?(host) and topath != frompath
      "cp -R #{frompath} #{topath}".bash
      "chown #{huser} #{topath}".bash if huser != ENV['LOGNAME']
    elsif host != Socket.gethostname
      return Basher.gate_scp('gateway',hostid,frompath,topath) if Socket.needs_gateway?
      Net::SCP.start(host,huser,hopts) do |scp|
        scp.upload!(frompath,topath,:recursive=>true)
      end
    end
    return true
  end

  def Basher.tmpfile(data,binary=false)
    #creates a file under tmp/files with an md5 from the data
    tmpfile_folder = "#{Rails.root}/tmp/files/"
    tmpfile_path = "#{tmpfile_folder}#{(data.to_s + Time.now.utc.to_f.to_s).to_md5}"
    FileUtils.mkpath(tmpfile_folder)
    write_mode = binary ? "wb" : "w"
    File.open(tmpfile_path,write_mode) {|f| f.print(data)}
    return tmpfile_path
  end

  def Basher.sh(hostid,commands,except=true,errlog=nil)
    host,hkeys,hport,huser = Basher.hosts[hostid].ie{|h| ['host','keys','port','user'].map{|k| h[k]}}
    hopts = {:port=>(hport||22),:keys=>hkeys}
    if hostid=='local'
      command = commands.to_a.join(";")
      #put command in file
      comm_folder = "#{Rails.root}/tmp/commands/#{command.to_md5}/"
      FileUtils.mkpath(comm_folder)
      FileUtils.mkpath(errlog[0..errlog.rindex("/")]) if (errlog and errlog.index("/") and !errlog.ends_with?("/"))
      comm_path = %{#{comm_folder}command.sh}
      errlog ||= %{#{comm_folder}error.log}
      File.open(comm_path,"w") {|f| f.print(command)}
      #make it executable
      stdo = `chmod +x #{comm_path} && . #{comm_path} 2> #{errlog}`
      stde = File.open("#{errlog}").read if File.exists?("#{errlog}")
      if stde and stde.length>0
        if except
          raise stde
        else
          return stdo
        end
      else
        return stdo
      end
    end
    return Basher.gate_sh('gateway',hostid,commands,except,errlog) if Socket.needs_gateway?
    Net::SSH.start(host,huser,hopts) do |ssh|
      if commands.class==Array
        if commands.length>1
          commands[1..-1].each{|c| ssh.exec_w_err(c)}
        end
        command = commands.last
      elsif commands.class==String
        command = commands
      end
      #this is the only one that gets returned
      return ssh.exec_w_err(command,except,errlog)
    end
  end
end
class Net::SSH::Connection::Session
  def exec_w_err(command,except=true,errlog=nil)
    result = ["",""]
    f = File.open(errlog,"a") if errlog
    self.exec!(command) do |ch, stream, data|
      if stream == :stderr
        result[-1] += data
        f.print(data) if f
      else
        result[0] += data
      end
    end
    f.close if f
    if result.last.length>0
      if except
        raise result.last
      else
        return result
      end
    else
      return result.first
    end
  end

end
class Net::SSH::Gateway
  def self.sh(ghost,guser,host,user,commands,gopts={},hopts={},except=true,errlog=nil)
    f = File.open(errlog,"a") if errlog
    gateway = self.new(ghost,guser,gopts)
    gateway.ssh(host,user,hopts) do |ssh|
      if commands.class==Array
        if commands.length>1
          commands[1..-1].each do |c|
            ssh.exec!(c) do |ch, stream, data|
              raise data if (except and stream == :stderr)
            end
          end
        end
        last_command = commands.last
      elsif commands.class==String
        last_command = commands
      end
      result = ["",""]
      ssh.exec!(last_command) do |ch, stream, data|
        if stream == :stderr
          result[-1] += data
          f.print(data) if f
        else
          result[0] += data
        end
      end
      f.close if f
      if result.last.length>0
        if except
          raise result.last
        else
          return result
        end
      else
        return result.first
      end
    end
  end
  def self.sync(ghost,guser,frompath,topath,tohost=Socket.gethostname,gopts={},fromopts={},toopts={},fromhost=Socket.gethostname,fromuser = ENV['LOGNAME'],touser=fromuser)
    gateway = self.new(ghost,guser,gopts)
    if fromhost == Socket.gethostname
      if tohost == Socket.gethostname and topath != frompath
        "cp #{frompath} #{topath}".bash
        "chown #{touser} #{topath}".bash if touser != fromuser
      elsif tohost != Socket.gethostname
        gateway.scp(tohost,touser,toopts) do |scp|
          scp.upload!(frompath,topath,:recursive=>true)
        end
      end
    else
      #download file to tmp path
      tmppath = %{#{Rails.root}/tmp/#{[fromhost,fromuser,frompath.gsub("/","_")].join("_")}}
      gateway.scp(fromhost,fromuser,fromopts) do |scp|
        scp.download!(frompath,tmppath,:recursive=>true)
      end
      if tohost == Socket.gethostname and topath != tmppath
        #move file to specified local path
        "mv #{tmppath} #{topath}".bash
      else
        #upload file to remote host
        gateway.scp(tohost,touser,toopts) do |scp|
          scp.upload!(tmppath,topath,:recursive=>true)
        end
        #make sure tmppath is removed
        "rm #{tmppath}".bash
      end
    end
    return true
  end
  #allow scp through gateway
  def scp(host, user, options={}, &block)
    local_port = open(host, options[:port] || 22)
    begin
      Net::SCP.start("127.0.0.1", user, options.merge(:port => local_port), &block)
    ensure
      close(local_port) if block || $!
    end
  end
end
