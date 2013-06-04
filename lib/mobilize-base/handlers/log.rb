module Mobilize
  module Log
    def Log.config
      Base.config('log')
    end

    def Log.path
      Log.config['path']
    end

    def Log.write(stage_path, handler, method, message)
      micro_timestamp = Time.now.to_f.to_s.split(".").instance_eval{|ta| [Time.at(ta.first.to_i).utc.to_s,ta.last[0..5]].join(" ")}
      prefix = "#{micro_timestamp}:#{stage_path}:#{handler}#{method}: "
      
      Logger.new(Log.path, 10, 1024*1000*10).info(log_string)
    end
  end
end
